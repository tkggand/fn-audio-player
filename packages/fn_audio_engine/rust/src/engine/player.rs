//! 播放核心：解码线程 → DSP 链 → 重采样 → 环形缓冲 → cpal 输出。
//!
//! * 解码线程负责网络拉流/解码/本地 DSP，块式推进，可被 seek 打断；
//! * 输出回调只从环形缓冲取样本，并统计"真正放出去的帧数"作为播放进度；
//! * 暂停/音量/停止都是共享状态里的原子开关，不重建音频设备。

use std::collections::VecDeque;
use std::io::{Read, Seek, SeekFrom};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

use crate::engine::crossfeed::CrossfeedSettings;
use crate::engine::dsd_stream::DsdStreamDecoder;
use crate::engine::net::HttpMediaSource;
use crate::engine::pcm::Planar;
use crate::engine::spectrum::SpectrumAnalyzer;
use crate::engine::stream_chain::{BlockChain, ChainOptions, ResampleStream};
use crate::engine::stream_decode::StreamDecoder;

/// 解码块大小（源采样率下的帧数，约 21–46 ms）。
const DECODE_BLOCK: usize = 4096;
/// 环形缓冲容量（秒）：LAN 拉流抖动足够用，也不至于让 seek 响应变慢。
const RING_SECONDS: f64 = 3.0;

/// 一次性加载参数（对应服务端 `ProcessOptions` 的客户端版本）。
#[derive(Clone)]
pub struct LoadOptions {
    /// CamillaDSP 预设 YAML（None = 直通）
    pub preset_yaml: Option<String>,
    /// PEQ/GEQ 配置 JSON（`/api/dsp/eq` 的 profile）
    pub eq_json: Option<String>,
    /// 交叉馈送设置 JSON（`/api/dsp/crossfeed`）
    pub crossfeed_json: Option<String>,
    /// ReplayGain 线性增益（None = 不调整）
    pub rg_gain: Option<f64>,
    /// 淡入/淡出（毫秒）
    pub fade_in_ms: f64,
    pub fade_out_ms: f64,
    /// 设备端音量（0.0–1.0），与 RG 增益分开：RG 在链里，音量在输出回调里
    pub volume: f64,
}

impl Default for LoadOptions {
    fn default() -> Self {
        Self {
            preset_yaml: None,
            eq_json: None,
            crossfeed_json: None,
            rg_gain: None,
            fade_in_ms: 0.0,
            fade_out_ms: 0.0,
            // 音量默认满格：Dart 侧未显式传时不应静音。
            volume: 1.0,
        }
    }
}

/// 播放状态快照（Dart 侧轮询）。
#[derive(Clone, Debug, Default)]
pub struct EngineStatus {
    /// 音频设备已就绪且媒体已打开（可以起播）
    pub ready: bool,
    pub playing: bool,
    /// 已播到文件末尾（Dart 侧据此切下一首）
    pub ended: bool,
    /// 当前播放位置（秒，绝对）
    pub position: f64,
    /// 时长（秒；未知为 0，由 UI 回退到曲库元数据）
    pub duration: f64,
    /// 已解码到的最远位置（秒）
    pub buffered: f64,
    /// 源采样率
    pub sample_rate: u32,
    /// 最近一次错误（解码/网络/设备）
    pub error: Option<String>,
}

struct Inner {
    playing: bool,
    discard: bool,
    volume: f32,
    pending_seek: Option<f64>,
    stop: bool,
    /// 解码线程代次：每次 load/stop 自增，旧线程发现代次不符即退出。
    /// 这样换曲时无需 join（避免网络卡顿时把 UI 线程一起挂住）。
    generation: u64,
    ring: VecDeque<f32>,
    ring_cap: usize,
    src_rate: u32,
    out_rate: u32,
    duration: f64,
    ready: bool,
    eof: bool,
    ended: bool,
    base_frames: u64,
    played_frames: u64,
    decoded_frames: u64,
    error: Option<String>,
    /// 输出端频谱（供 UI 绘制，对齐 Web 频谱柱）。
    spectrum: SpectrumAnalyzer,
}

impl Inner {
    fn new() -> Self {
        Self {
            playing: false,
            discard: false,
            volume: 1.0,
            pending_seek: None,
            stop: false,
            generation: 0,
            ring: VecDeque::new(),
            ring_cap: 0,
            src_rate: 0,
            out_rate: 0,
            duration: 0.0,
            ready: false,
            eof: false,
            ended: false,
            base_frames: 0,
            played_frames: 0,
            decoded_frames: 0,
            error: None,
            spectrum: SpectrumAnalyzer::new(),
        }
    }

    fn position_secs(&self) -> f64 {
        if self.out_rate == 0 {
            return 0.0;
        }
        (self.base_frames + self.played_frames) as f64 / self.out_rate as f64
    }

    fn buffered_secs(&self) -> f64 {
        if self.out_rate == 0 {
            return 0.0;
        }
        (self.base_frames + self.decoded_frames) as f64 / self.out_rate as f64
    }

    fn reset_for_load(&mut self, opts: &LoadOptions) {
        self.playing = false;
        self.discard = true;
        self.volume = (opts.volume as f32).clamp(0.0, 1.0);
        self.pending_seek = None;
        self.stop = false;
        self.ring.clear();
        self.ready = false;
        self.eof = false;
        self.ended = false;
        self.base_frames = 0;
        self.played_frames = 0;
        self.decoded_frames = 0;
        self.error = None;
        self.src_rate = 0;
        self.duration = 0.0;
        self.spectrum.reset();
    }
}

struct Shared {
    inner: Mutex<Inner>,
    cv: Condvar,
    /// iOS：系统打断（来电 / 其他 App 播放）会停下 RemoteIO 音频单元，
    /// 再次起播时由音频线程重新激活会话并重启音频单元。
    #[cfg(target_os = "ios")]
    restart_stream: AtomicBool,
}

impl Shared {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// 全局播放器：音频线程常驻，解码线程按曲目重建。
pub struct Player {
    shared: Arc<Shared>,
    decode: Option<JoinHandle<()>>,
    quit: Arc<AtomicBool>,
    /// 音频线程是否已成功建立输出流（失败时 Dart 回退 just_audio）。
    device_ok: Arc<AtomicBool>,
    audio_thread: Option<JoinHandle<()>>,
}

unsafe impl Send for Player {}
unsafe impl Sync for Player {}

impl Player {
    pub fn new() -> Self {
        let shared = Arc::new(Shared {
            inner: Mutex::new(Inner::new()),
            cv: Condvar::new(),
            #[cfg(target_os = "ios")]
            restart_stream: AtomicBool::new(false),
        });
        let device_ok = Arc::new(AtomicBool::new(false));
        let quit = Arc::new(AtomicBool::new(false));
        let out_rate = Arc::new(AtomicU64::new(48_000));

        let audio_thread = {
            let shared = shared.clone();
            let device_ok = device_ok.clone();
            let quit = quit.clone();
            let out_rate = out_rate.clone();
            let panic_shared = shared.clone();
            std::thread::Builder::new()
                .name("fn-audio-out".into())
                .spawn(move || {
                    // 后端（如 cpal 的 AAudio）可能因缺少平台初始化而 panic。
                    // 捕获后写回错误，Dart 侧才能显示真实原因而不是"未知原因"。
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        audio_thread_main(shared, device_ok, quit, out_rate);
                    }));
                    if let Err(payload) = result {
                        let msg = payload
                            .downcast_ref::<&str>()
                            .map(|s| s.to_string())
                            .or_else(|| payload.downcast_ref::<String>().cloned())
                            .unwrap_or_else(|| "未知 panic".into());
                        crate::engine::log::warn(&format!("音频线程崩溃: {msg}"));
                        panic_shared.lock().error = Some(format!("音频线程崩溃: {msg}"));
                    }
                })
                .ok()
        };

        Self {
            shared,
            decode: None,
            quit,
            device_ok,
            audio_thread,
        }
    }

    /// 打开设备后的实际输出采样率（设备未就绪时返回 0）。
    pub fn output_rate(&self) -> u32 {
        self.shared.lock().out_rate
    }

    pub fn device_ok(&self) -> bool {
        self.device_ok.load(Ordering::SeqCst)
    }

    /// 加载一首（会替换当前解码线程）。
    pub fn load(&mut self, url: String, start_sec: f64, opts: LoadOptions) {
        // 旧解码线程立即作废（代次自增），但不 join：它可能正卡在 20s 网络超时里，
        // 在 UI 线程上等待会表现为"点了没反应"。旧线程在下一次循环检查时自行退出。
        let gen;
        {
            let mut inner = self.shared.lock();
            inner.stop = true;
            inner.playing = false;
            inner.generation += 1;
            inner.ring.clear();
            inner.reset_for_load(&opts);
            gen = inner.generation;
            inner.stop = false;
        }
        self.shared.cv.notify_all();

        let out_rate = self.shared.lock().out_rate.max(1);
        let shared = self.shared.clone();
        if let Some(h) = self.decode.take() {
            drop(h); // 分离旧线程，不等它退出
        }
        self.decode = std::thread::Builder::new()
            .name("fn-audio-decode".into())
            .spawn(move || decode_thread_main(shared, url, opts, start_sec.max(0.0), out_rate, gen))
            .ok();
    }

    pub fn play(&self) {
        let mut inner = self.shared.lock();
        if inner.error.is_some() && !inner.ready {
            return;
        }
        inner.playing = true;
        inner.ended = false;
        drop(inner);
        // iOS：cpal 只在「打断结束」通知里自行恢复音频单元，覆盖不到 App 被别的
        // App 打断后手动再起播的场景，这里让音频线程每次都确保会话已激活、单元已启动。
        #[cfg(target_os = "ios")]
        self.shared.restart_stream.store(true, Ordering::SeqCst);
        self.shared.cv.notify_all();
    }

    pub fn pause(&self) {
        let mut inner = self.shared.lock();
        inner.playing = false;
        drop(inner);
        self.shared.cv.notify_all();
    }

    pub fn seek(&self, secs: f64) {
        let mut inner = self.shared.lock();
        inner.pending_seek = Some(secs.max(0.0));
        inner.discard = true;
        inner.ended = false;
        // 关键：立刻丢掉旧缓冲。discard 期间输出回调不再取样本，环形缓冲会保持满，
        // 解码线程就卡在 push_planar 等空间，永远轮不到处理这次 seek（死锁 → 拖动无反应）。
        inner.ring.clear();
        drop(inner);
        self.shared.cv.notify_all();
        crate::engine::log::info(&format!("seek 请求 {:.2}s", secs));
    }

    pub fn set_volume(&self, v: f64) {
        let mut inner = self.shared.lock();
        inner.volume = (v as f32).clamp(0.0, 1.0);
    }

    pub fn status(&self) -> EngineStatus {
        let inner = self.shared.lock();
        EngineStatus {
            ready: inner.ready,
            playing: inner.playing && !inner.ended,
            ended: inner.ended,
            position: inner.position_secs(),
            duration: inner.duration,
            buffered: inner.buffered_secs(),
            sample_rate: inner.src_rate,
            error: inner.error.clone(),
        }
    }

    /// 当前输出频谱（0.0–1.0，长度 [`crate::engine::spectrum::BARS`]）。
    pub fn spectrum(&self) -> Vec<f32> {
        self.shared.lock().spectrum.values().to_vec()
    }

    pub fn stop(&mut self) {
        {
            let mut inner = self.shared.lock();
            inner.stop = true;
            inner.generation += 1;
            inner.playing = false;
            inner.pending_seek = None;
            inner.ring.clear();
            inner.ready = false;
            inner.spectrum.reset();
        }
        self.shared.cv.notify_all();
        // 与 load 一致：不 join，旧线程下一次循环检查时自行退出。
        self.decode.take();
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        self.stop();
        self.quit.store(true, Ordering::SeqCst);
        self.shared.cv.notify_all();
        if let Some(h) = self.audio_thread.take() {
            let _ = h.join();
        }
    }
}

/// 音频线程：建立默认输出设备，回调里从环形缓冲取样本。
fn audio_thread_main(
    shared: Arc<Shared>,
    device_ok: Arc<AtomicBool>,
    quit: Arc<AtomicBool>,
    out_rate: Arc<AtomicU64>,
) {
    crate::engine::log::info("音频线程启动");
    let host = cpal::default_host();
    let device = match host.default_output_device() {
        Some(d) => d,
        None => {
            crate::engine::log::warn("没有可用的音频输出设备");
            let mut inner = shared.lock();
            inner.error = Some("没有可用的音频输出设备".into());
            return;
        }
    };
    crate::engine::log::info("已获取默认输出设备");

    // 优先使用设备默认（共享模式混音）格式：它与系统实际混音采样率一致，
    // 避免选到设备支持的最高采样率（如 192k）——那会让 44.1k 源做十几倍重采样，
    // 既费 CPU 又容易欠载，低频被拉长的中间态听起来就是“破音/发飘”。
    let config = device
        .default_output_config()
        .ok()
        .filter(|c| c.sample_format() == cpal::SampleFormat::F32)
        .or_else(|| {
            device
                .supported_output_configs()
                .ok()
                .and_then(|mut list| {
                    list.find(|c| {
                        c.sample_format() == cpal::SampleFormat::F32
                            && c.channels() >= 2
                    })
                    .map(|c| {
                        // 无默认格式时，区间内含 48k 就用 48k，否则取区间上限。
                        let lo = c.min_sample_rate();
                        let hi = c.max_sample_rate();
                        c.with_sample_rate(48_000u32.clamp(lo, hi))
                    })
                })
        });

    let config = match config {
        Some(c) => c,
        None => {
            crate::engine::log::warn("输出设备不支持 f32 采样格式");
            let mut inner = shared.lock();
            inner.error = Some("输出设备不支持 f32 采样格式".into());
            return;
        }
    };
    crate::engine::log::info(&format!(
        "输出设备: {} Hz / {} ch / {:?}",
        config.sample_rate(),
        config.channels(),
        config.sample_format()
    ));

    let rate = config.sample_rate();
    let channels = config.channels() as usize;
    {
        let mut inner = shared.lock();
        inner.out_rate = rate;
        let cap = (RING_SECONDS * rate as f64) as usize * 2;
        inner.ring_cap = cap.max(rate as usize * 2);
    }
    out_rate.store(rate as u64, Ordering::SeqCst);

    let stream_config: cpal::StreamConfig = config.into();
    let callback_shared = shared.clone();
    crate::engine::log::info("正在创建输出流");
    let stream = match device.build_output_stream(
        stream_config,
        move |data: &mut [f32], _| fill_output(&callback_shared, data, channels),
        |e| crate::engine::log::warn(&format!("输出流错误: {e}")),
        None,
    ) {
        Ok(s) => {
            crate::engine::log::info("输出流已创建");
            s
        }
        Err(e) => {
            crate::engine::log::warn(&format!("创建输出流失败: {e}"));
            let mut inner = shared.lock();
            inner.error = Some(format!("创建输出流失败: {e}"));
            return;
        }
    };
    // iOS：先激活音频会话再启动音频单元，否则 RemoteIO 会以静音渲染
    // （cpal 不会自己激活会话；其他平台是空实现）。
    crate::engine::ios::activate_session();
    if stream.play().is_err() {
        crate::engine::log::warn("启动输出流失败");
        let mut inner = shared.lock();
        inner.error = Some("启动输出流失败".into());
        return;
    }
    crate::engine::log::info("输出流已启动");
    device_ok.store(true, Ordering::SeqCst);

    while !quit.load(Ordering::SeqCst) {
        // iOS：系统打断后音频单元可能已被系统停下，起播时重新激活会话并重启它。
        #[cfg(target_os = "ios")]
        if shared.restart_stream.swap(false, Ordering::SeqCst) {
            crate::engine::ios::activate_session();
            if let Err(e) = stream.play() {
                crate::engine::log::warn(&format!("重启输出流失败: {e}"));
            }
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    drop(stream);
}

/// 输出回调：只做取样本 + 音量 + 进度计数，绝不做解码/DSP。
fn fill_output(shared: &Arc<Shared>, data: &mut [f32], channels: usize) {
    let mut inner = shared.lock();
    let frames = data.len() / channels.max(1);
    let playing = inner.playing && !inner.discard && !inner.stop;
    // 静音（seek / 失败）期间也要持续排空旧缓冲：否则缓冲一直是满的，
    // 解码线程等不到空间，seek 请求无法被处理。
    if inner.discard {
        inner.ring.clear();
    }
    let volume = inner.volume;
    let rate = inner.out_rate;

    for f in 0..frames {
        let base = f * channels;
        if !playing || inner.ring.len() < 2 {
            for c in 0..channels {
                data[base + c] = 0.0;
            }
            inner.spectrum.push(0.0, 0.0, rate);
            if playing && inner.ring.len() < 2 && inner.eof {
                inner.ended = true;
            }
            continue;
        }
        let l = inner.ring.pop_front().unwrap_or(0.0) * volume;
        let r = inner.ring.pop_front().unwrap_or(0.0) * volume;
        inner.spectrum.push(l, r, rate);
        match channels {
            1 => data[base] = (l + r) * 0.5,
            2 => {
                data[base] = l;
                data[base + 1] = r;
            }
            _ => {
                data[base] = l;
                data[base + 1] = r;
                for c in 2..channels {
                    data[base + c] = 0.0;
                }
            }
        }
        inner.played_frames += 1;
    }
}

enum Media {
    Symphonia(StreamDecoder),
    Dsd(DsdStreamDecoder),
}

impl Media {
    fn sample_rate(&self) -> u32 {
        match self {
            Media::Symphonia(d) => d.sample_rate(),
            Media::Dsd(d) => d.sample_rate(),
        }
    }
    fn duration_secs(&self) -> Option<f64> {
        match self {
            Media::Symphonia(d) => d.duration_secs(),
            Media::Dsd(d) => d.duration_secs(),
        }
    }
    fn next_block(&mut self, max_frames: usize) -> anyhow::Result<Option<Planar>> {
        match self {
            Media::Symphonia(d) => d.next_block(max_frames),
            Media::Dsd(d) => d.next_block(max_frames),
        }
    }
    fn seek_secs(&mut self, secs: f64) -> anyhow::Result<()> {
        match self {
            Media::Symphonia(d) => d.seek_secs(secs),
            Media::Dsd(d) => d.seek_secs(secs),
        }
    }
}

fn open_media(url: &str) -> anyhow::Result<Media> {
    let mut source = HttpMediaSource::open(url)?;
    let mut magic = [0u8; 4];
    let is_dsd = source
        .read_exact(&mut magic)
        .map(|_| &magic == b"DSD " || &magic == b"FRM8")
        .unwrap_or(false);
    source.seek(SeekFrom::Start(0))?;
    if is_dsd {
        Ok(Media::Dsd(DsdStreamDecoder::open(Box::new(source))?))
    } else {
        Ok(Media::Symphonia(StreamDecoder::open(Box::new(source), None)?))
    }
}

fn decode_thread_main(
    shared: Arc<Shared>,
    url: String,
    opts: LoadOptions,
    start_sec: f64,
    out_rate: u32,
    gen: u64,
) {
    let mut media = match open_media(&url) {
        Ok(m) => m,
        Err(e) => {
            let mut inner = shared.lock();
            if inner.generation == gen {
                inner.error = Some(format!("打开音频流失败: {e}"));
                inner.discard = true;
            }
            return;
        }
    };

    let src_rate = media.sample_rate();
    let duration = media.duration_secs().unwrap_or(0.0);
    let total_frames = (duration * src_rate as f64).round() as usize;

    let crossfeed = opts
        .crossfeed_json
        .as_deref()
        .and_then(|j| CrossfeedSettings::from_json(j).ok())
        .unwrap_or_default();
    let chain_opts = ChainOptions {
        preset_yaml: opts.preset_yaml.as_deref(),
        eq_json: opts.eq_json.as_deref(),
        rg_linear: opts.rg_gain,
        crossfeed,
        fade_in_ms: opts.fade_in_ms,
        fade_out_ms: opts.fade_out_ms,
    };
    let mut chain = match BlockChain::new(&chain_opts, src_rate, Some(total_frames)) {
        Ok(c) => c,
        Err(e) => {
            let mut inner = shared.lock();
            if inner.generation == gen {
                inner.error = Some(format!("构建 DSP 链失败: {e}"));
                inner.discard = true;
            }
            return;
        }
    };
    let mut resampler = make_resampler(src_rate, out_rate);

    {
        let mut inner = shared.lock();
        if inner.generation != gen {
            return;
        }
        inner.src_rate = src_rate;
        inner.duration = duration;
        inner.ready = true;
        // seek 到起点（0 也要显式对齐，保证解码器状态干净）
        inner.base_frames = (start_sec * out_rate as f64).round() as u64;
        inner.played_frames = 0;
        inner.decoded_frames = 0;
        inner.discard = false;
    }
    if start_sec > 0.0 {
        if media.seek_secs(start_sec).is_err() {
            let _ = media.seek_secs(0.0);
        }
        chain.reset_position((start_sec * src_rate as f64) as usize);
    }

    let mut eof = false;
    loop {
        // 1) 控制面：停止 / seek / 暂停
        let mut inner = shared.lock();
        if inner.stop || inner.generation != gen {
            return;
        }
        if let Some(target) = inner.pending_seek.take() {
            inner.discard = true;
            inner.ring.clear();
            inner.eof = false;
            inner.ended = false;
            inner.base_frames = (target * out_rate as f64).round() as u64;
            inner.played_frames = 0;
            inner.decoded_frames = 0;
            drop(inner);
            if let Err(e) = media.seek_secs(target) {
                crate::engine::log::warn(&format!("seek 失败 {target:.2}s: {e}"));
                let mut inner = shared.lock();
                if inner.generation == gen {
                    inner.error = Some(format!("seek 失败: {e}"));
                    inner.discard = false;
                }
                continue;
            }
            crate::engine::log::info(&format!("seek 完成 {target:.2}s"));
            chain.reset_position((target * src_rate as f64) as usize);
            resampler = make_resampler(src_rate, out_rate);
            eof = false;
            let mut inner = shared.lock();
            inner.discard = false;
            drop(inner);
            shared.cv.notify_all();
            continue;
        }
        let playing = inner.playing;
        let room = inner.ring.len() < inner.ring_cap;
        drop(inner);
        if !playing || !room {
            let guard = shared.lock();
            let _ = shared
                .cv
                .wait_timeout(guard, Duration::from_millis(20))
                .ok();
            continue;
        }

        // 2) 解码一块（源采样率）
        if eof {
            // 缓冲已灌满且已到尾部：等回调把数据放完
            let guard = shared.lock();
            let _ = shared
                .cv
                .wait_timeout(guard, Duration::from_millis(20))
                .ok();
            continue;
        }

        let block = match media.next_block(DECODE_BLOCK) {
            Ok(Some(b)) => b,
            Ok(None) => {
                eof = true;
                // 重采样器里还压着少量帧，冲出来再标 EOF，否则每首歌尾部会掉几十毫秒。
                if let Some(mut rs) = resampler.take() {
                    match rs.flush() {
                        Ok(tail) if !tail.is_empty() && !tail[0].is_empty() => {
                            push_planar(&shared, &tail, gen);
                        }
                        Ok(_) => {}
                        Err(e) => crate::engine::log::warn(&format!("冲刷重采样器失败: {e}")),
                    }
                }
                let mut inner = shared.lock();
                if inner.generation == gen {
                    inner.eof = true;
                }
                drop(inner);
                continue;
            }
            Err(e) => {
                let mut inner = shared.lock();
                if inner.generation == gen {
                    inner.error = Some(format!("解码失败: {e}"));
                    inner.eof = true;
                }
                drop(inner);
                continue;
            }
        };

        let mut planar = chain.process(block);
        let out = match resampler.as_mut() {
            Some(rs) => match rs.push(&planar) {
                Ok(o) => o,
                Err(e) => {
                    let mut inner = shared.lock();
                    if inner.generation == gen {
                        inner.error = Some(format!("重采样失败: {e}"));
                        inner.discard = true;
                    }
                    return;
                }
            },
            None => std::mem::take(&mut planar),
        };
        if out.is_empty() || out[0].is_empty() {
            continue;
        }
        push_planar(&shared, &out, gen);
    }
}

/// 设备输出率与源采样率不一致时建一个 FFT 重采样器（立体声）。
fn make_resampler(src_rate: u32, out_rate: u32) -> Option<ResampleStream> {
    if src_rate == out_rate {
        return None;
    }
    ResampleStream::new(src_rate, out_rate, 2).ok()
}

/// 把 planar 立体声推到环形缓冲（满时等待回调消费）。
///
/// `gen` 是发起它的解码线程代次：换曲后旧线程发现代次不符立即放弃写入。
fn push_planar(shared: &Arc<Shared>, planar: &Planar, gen: u64) {
    let frames = planar[0].len();
    let mut i = 0usize;
    while i < frames {
        let mut inner = shared.lock();
        if inner.stop || inner.generation != gen {
            return;
        }
        if inner.ring.len() < inner.ring_cap {
            let room = (inner.ring_cap - inner.ring.len()) / 2;
            let take = room.min(frames - i);
            let right = planar.get(1).map(|r| r.as_slice()).unwrap_or(&planar[0]);
            for k in 0..take {
                inner.ring.push_back(planar[0][i + k] as f32);
                inner.ring.push_back(right[i + k] as f32);
            }
            inner.decoded_frames += take as u64;
            i += take;
        } else {
            drop(inner);
            let guard = shared.lock();
            let _ = shared
                .cv
                .wait_timeout(guard, Duration::from_millis(20))
                .ok();
        }
    }
}

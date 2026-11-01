//! Dart ↔ Rust 桥接面（flutter_rust_bridge）。
//!
//! 只有这一层知道"全局单例播放器"存在；`engine::player` 保持可测试的纯结构，
//! 不依赖任何 FFI 上下文。Dart 侧拿到的都是纯值类型，避免跨语言持有借用。

use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use flutter_rust_bridge::frb;

use crate::engine::player::{EngineStatus, LoadOptions, Player};

/// 全局播放器（音频线程常驻；解码线程按曲目重建）。
fn player() -> &'static Mutex<Player> {
    static PLAYER: OnceLock<Mutex<Player>> = OnceLock::new();
    PLAYER.get_or_init(|| Mutex::new(Player::new()))
}

fn lock() -> std::sync::MutexGuard<'static, Player> {
    player().lock().unwrap_or_else(|e| e.into_inner())
}

/// 加载参数（Dart 侧构造后一次传入，避免多次跨语言调用）。
#[derive(Clone, Debug)]
pub struct EngineOptions {
    /// CamillaDSP 预设 YAML（空串 = 直通）
    pub preset_yaml: String,
    /// PEQ/GEQ 配置 JSON（空串 = 不启用）
    pub eq_json: String,
    /// 交叉馈送设置 JSON（空串 = 不启用）
    pub crossfeed_json: String,
    /// ReplayGain 线性增益（0 = 不调整）
    pub rg_gain: f64,
    pub fade_in_ms: f64,
    pub fade_out_ms: f64,
    /// 音量（0.0–1.0）
    pub volume: f64,
}

impl Default for EngineOptions {
    fn default() -> Self {
        Self {
            preset_yaml: String::new(),
            eq_json: String::new(),
            crossfeed_json: String::new(),
            rg_gain: 0.0,
            fade_in_ms: 0.0,
            fade_out_ms: 0.0,
            volume: 1.0,
        }
    }
}

impl EngineOptions {
    fn into_load_options(self) -> LoadOptions {
        LoadOptions {
            preset_yaml: (!self.preset_yaml.is_empty()).then_some(self.preset_yaml),
            eq_json: (!self.eq_json.is_empty()).then_some(self.eq_json),
            crossfeed_json: (!self.crossfeed_json.is_empty()).then_some(self.crossfeed_json),
            rg_gain: (self.rg_gain > 0.0).then_some(self.rg_gain),
            fade_in_ms: self.fade_in_ms,
            fade_out_ms: self.fade_out_ms,
            volume: self.volume,
        }
    }
}

/// 初始化音频设备并返回是否可用。
///
/// 音频线程是异步建流的，这里最多等 `timeout_ms` 毫秒；返回 `false` 时
/// Dart 侧应回退到 just_audio（每首歌仍各自判断一次）。
pub fn engine_init(timeout_ms: u64) -> bool {
    crate::install_panic_logger();
    let deadline = Instant::now() + Duration::from_millis(timeout_ms.min(3000));
    loop {
        if lock().device_ok() {
            return true;
        }
        if Instant::now() >= deadline {
            return false;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

/// 加载并准备播放一首（不自动起播，需再调 [`engine_play`]）。
#[frb(sync)]
pub fn engine_load(url: String, start_sec: f64, opts: EngineOptions) -> EngineStatus {
    let mut p = lock();
    p.load(url, start_sec.max(0.0), opts.into_load_options());
    p.status()
}

#[frb(sync)]
pub fn engine_play() {
    lock().play();
}

#[frb(sync)]
pub fn engine_pause() {
    lock().pause();
}

#[frb(sync)]
pub fn engine_seek(secs: f64) {
    lock().seek(secs);
}

#[frb(sync)]
pub fn engine_set_volume(volume: f64) {
    lock().set_volume(volume);
}

#[frb(sync)]
pub fn engine_stop() {
    lock().stop();
}

/// 状态快照（Dart 侧每帧/定时轮询）。
#[frb(sync)]
pub fn engine_status() -> EngineStatus {
    lock().status()
}

/// 设备实际输出采样率（0 = 未就绪）。
#[frb(sync)]
pub fn engine_output_rate() -> u32 {
    lock().output_rate()
}

/// 实时输出频谱（28 根柱子，0.0–1.0），与 Web 端可视化一致。
///
/// 数值来自本地引擎的输出回调；未启用本地引擎（走 just_audio）时恒为 0，
/// Dart 侧应改为绘制静态示意柱。
#[frb(sync)]
pub fn engine_spectrum() -> Vec<f32> {
    lock().spectrum()
}

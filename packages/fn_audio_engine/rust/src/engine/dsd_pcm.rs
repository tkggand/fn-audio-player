//! DSD → PCM 抽取滤波，与 DSD over PCM（DoP）打包。
//!
//! # 为什么 DSD 不能直接当 PCM 送
//!
//! DSD 是**1 bit、极高采样率**的流（DSD64 = 2.8224 MHz），噪声在高频呈"白噪声梯形"分布，
//! 要变成音频必须先**低通 + 抽取**。不做这一步直接送进声卡，听到的是一片嘶嘶声。
//!
//! # 抽取滤波器：两级 ×8，而不是一级 ×64
//!
//! 单级抽取要把滤波器截止压到 0.45/64 ≈ 0.007 fs，需要几百抽头才能压住镜像，
//! 而 DSD64 立体声每秒要做 `2.82M × 几百` 次乘加——一首歌几分钟 CPU。
//!
//! 两级各抽 8 倍（2.8224 MHz → 352.8 kHz → 44.1 kHz）：
//!
//! - 第一级：32 抽头，截止 0.45/8，跑在 2.8224 MHz 上 → 每秒约 0.09 GMAC；
//! - 第二级：32 抽头，截止 0.45/8，跑在 352.8 kHz 上 → 每秒约 0.01 GMAC。
//!
//! 总代价约 1/10，而两级级联的有效滚降远比一级陡：两级 Blackman-Harris 叠加
//! 在阻带能到 −100 dB 以上，一级 256 抽头也就 −80 dB 上下。**便宜且更干净**。
//!
//! # SACD 增益
//!
//! DSD64 转 44.1 kHz 后整体偏低约 6 dB（SACD 的电平约定），行业惯例补 +6 dB
//! （`DSD_SACD_GAIN = 2.0`）。补完再限幅到 ±1，避免整数化时回绕成爆音。
//!
//! # DoP 是什么
//!
//! DoP 把 DSD 装进 24 位 PCM：低 16 位放 16 个 DSD bit，高 8 位放**逐帧交替**
//! 的标志 `0x05` / `0xFA`。DAC 靠看到这个交替才切进 DSD 模式。
//!
//! **任何对这个 24 位字做乘法/重采样的处理都会改写标志字节，DAC 随即哑掉。**
//! 所以 DoP 流的 EQ、ReplayGain、淡入淡出必须全部旁路——见 [`dop_survives`]。

use std::f64::consts::PI;

use crate::engine::dsd::{DsdInfo, DsdReader};

/// SACD/DSD64 转 PCM 的惯例增益（+6 dB）。
pub const DSD_SACD_GAIN: f64 = 2.0;

/// 每级抽取倍数（两级共 64）。
const STAGE_FACTOR: usize = 8;

/// 每级 FIR 抽头数。32 + Blackman-Harris 的阻带衰减约 −90 dB，级联两遍够用。
const STAGE_TAPS: usize = 32;

/// 单级抽取的归一化截止频率（相对输入采样率）。
const STAGE_CUTOFF: f64 = 0.45;

/// 由 DSD 采样率选 PCM 输出率。
///
/// **默认落到 44.1 kHz**（能整除时）：CD 的采样率，带宽最小、与曲库其余资源同速，
/// 混播时不必重采样。DSD128/256 因此也降到 44.1 kHz——要满带宽输出用
/// [`choose_output_rate_high`]。不能整除时退回 `rate / 64`。
pub fn choose_output_rate(dsd_rate: u32) -> u32 {
    const FAMILY: [u32; 4] = [44_100, 88_200, 176_400, 48_000];
    for r in FAMILY {
        if dsd_rate.is_multiple_of(r) {
            return r;
        }
    }
    (dsd_rate / 64).max(1)
}

/// 设计低通 FIR：加窗 sinc（Blackman-Harris 窗），直流增益归一。
fn design_lowpass_fir(length: usize, factor: usize) -> Vec<f64> {
    let mut c = vec![0.0f64; length];
    let cutoff = STAGE_CUTOFF / factor as f64;
    let center = (length - 1) as f64 / 2.0;
    for (i, coef) in c.iter_mut().enumerate() {
        let x = i as f64 - center;
        let sinc = if x.abs() < 1e-10 {
            2.0 * cutoff
        } else {
            (2.0 * PI * cutoff * x).sin() / x
        };
        let n = i as f64 / (length - 1) as f64;
        // Blackman-Harris
        let w = 0.35875 - 0.48829 * (2.0 * PI * n).cos() + 0.14128 * (4.0 * PI * n).cos()
            - 0.01168 * (6.0 * PI * n).cos();
        *coef = sinc * w;
    }
    let sum: f64 = c.iter().sum();
    if sum.abs() > 1e-12 {
        for coef in c.iter_mut() {
            *coef /= sum;
        }
    }
    c
}

/// 一级"抽取 by N + FIR"流式级。
struct FirDecimator {
    factor: usize,
    coeffs: Vec<f64>,
    /// 每声道的历史样本（环形缓冲，最新在末尾）。
    history: Vec<Vec<f64>>,
    /// **每声道独立**的抽取相位：共用一个相位会让声道互相错位，
    /// 分块喂入时左右声道帧数对不齐。
    counters: Vec<usize>,
    out_rate: u32,
}

impl FirDecimator {
    fn new(channels: usize, in_rate: u32, factor: usize) -> Self {
        Self {
            factor,
            coeffs: design_lowpass_fir(STAGE_TAPS, factor),
            history: vec![vec![0.0; STAGE_TAPS - 1]; channels],
            counters: vec![0; channels],
            out_rate: (in_rate as u64 / factor as u64) as u32,
        }
    }

    fn out_rate(&self) -> u32 {
        self.out_rate
    }

    /// 推入一条通道的样本，抽取时把结果 append 到 `out`。
    fn push_channel(&mut self, ch: usize, samples: &[f64], out: &mut Vec<f64>) {
        let hist = &mut self.history[ch];
        for &x in samples {
            hist.push(x);
            self.counters[ch] += 1;
            if self.counters[ch] < self.factor {
                continue;
            }
            self.counters[ch] = 0;
            let n = hist.len();
            // hist[n-t] 对应 t = 0..TAPS-1 的最新样本开始回溯。
            let mut acc = 0.0;
            for (t, coef) in self.coeffs.iter().enumerate() {
                acc += coef * hist[n - 1 - t];
            }
            out.push(acc);
            hist.remove(0);
        }
    }
}

/// 流式 DSD → PCM 转换器（两级抽取，内存与曲长无关）。
pub struct DsdToPcm {
    stage1: FirDecimator,
    stage2: FirDecimator,
    /// 第一级的输出累积区。
    mid: Vec<Vec<f64>>,
    /// `mid` 里已经喂过第二级的位置（游标；清空会导致重复处理）。
    mid_pos: Vec<usize>,
    /// 上一块剩下不足 `channels` 字节的尾巴（块长不整除声道数时不能丢样本）。
    carry: Vec<u8>,
    gain: f64,
    /// 输出声道数。
    channels: usize,
}

impl DsdToPcm {
    pub fn new(channels: usize, dsd_rate: u32) -> Self {
        let out_rate = choose_output_rate(dsd_rate);
        Self::with_output_rate(channels, dsd_rate, out_rate)
    }

    /// 指定输出率的构造器（默认构造走 [`choose_output_rate`]）。
    pub fn with_output_rate(channels: usize, dsd_rate: u32, out_rate: u32) -> Self {
        let ratio = (dsd_rate / out_rate.max(1)).max(1) as usize;
        // 两级拆分：第一级固定 8（跑在高采样率上），第二级吃掉剩下的倍率。
        // 常见倍率：64 → 8×8、32 → 8×4、128 → 8×16。
        let first = if ratio >= 16 { STAGE_FACTOR } else { ratio };
        let second = (ratio / first).max(1);
        let stage1 = FirDecimator::new(channels, dsd_rate, first);
        let stage2 = FirDecimator::new(channels, stage1.out_rate(), second);
        Self {
            stage1,
            stage2,
            mid: vec![Vec::new(); channels],
            mid_pos: vec![0; channels],
            carry: Vec::new(),
            gain: DSD_SACD_GAIN,
            channels,
        }
    }

    /// PCM 输出采样率。
    pub fn output_rate(&self) -> u32 {
        self.stage2.out_rate()
    }

    /// 覆盖转换增益（默认 +6 dB，见 `DSD_SACD_GAIN`）。
    pub fn set_gain(&mut self, gain: f64) {
        self.gain = gain;
    }

    /// 把一段字节交织的 DSD 数据转成 PCM（append 到 `out`）。
    ///
    /// `lsb_first` 为真时按位反转：DSF 的位序与 DoP/PCM 约定相反。
    #[allow(clippy::ptr_arg)]
    pub fn push_bytes(&mut self, data: &[u8], lsb_first: bool, out: &mut Vec<Vec<f64>>) {
        if self.channels == 0 {
            return;
        }
        let bytes_per_byte_time = self.channels;
        let mut buf = std::mem::take(&mut self.carry);
        buf.extend_from_slice(data);
        let usable = buf.len() - (buf.len() % self.channels);
        let times = usable / bytes_per_byte_time;
        if times == 0 {
            self.carry = buf;
            return;
        }
        let data = &buf[..usable];
        // 余下的字节留给下一块：块长不整除声道数时，每块直接丢余数会持续掉样本。
        self.carry.clear();
        self.carry.extend_from_slice(&buf[usable..]);
        // 1 bit → ±1.0。位序在这里一次性定好，后面两级滤波都只看数值。
        // 每个 bit 展开成一个 ±1.0 样本：不能把一个字节折算成 1 个样本——
        // 那等于把 2.8224 MHz 假装成 352.8 kHz，高频噪声会直接混叠进可听频带。
        let mut tmp = vec![0.0f64; times * 8];
        for ch in 0..self.channels {
            for t in 0..times {
                let b = data[t * bytes_per_byte_time + ch];
                let v = if lsb_first { crate::engine::dsd::reverse_bits(b) } else { b };
                for bit in 0..8 {
                    tmp[t * 8 + bit] = if v & (0x80 >> bit) != 0 { 1.0 } else { -1.0 };
                }
            }
            self.stage1.push_channel(ch, &tmp, &mut self.mid[ch]);
        }
        // 只把**新增**的中间样本喂给第二级：整段重喂会把旧样本再算一遍。
        for (ch, mid) in self.mid.iter_mut().enumerate() {
            let pos = self.mid_pos[ch].min(mid.len());
            if pos < mid.len() {
                let tail: Vec<f64> = mid[pos..].to_vec();
                self.stage2.push_channel(ch, &tail, &mut out[ch]);
                self.mid_pos[ch] = mid.len();
            }
        }
    }

    /// 收尾：把两级里剩下的不足一块的尾数抽干。
    #[allow(clippy::ptr_arg)]
    pub fn flush(&mut self, out: &mut Vec<Vec<f64>>) {
        for (ch, mid) in self.mid.iter().enumerate() {
            let pos = self.mid_pos[ch].min(mid.len());
            if pos >= mid.len() {
                continue;
            }
            let tail: Vec<f64> = mid[pos..].to_vec();
            self.stage2.push_channel(ch, &tail, &mut out[ch]);
            self.mid_pos[ch] = mid.len();
        }
    }

    /// 增益 + 限幅（转 24 位整数前的最后一步）。
    pub fn apply_gain(&mut self, pcm: &mut [Vec<f64>]) {
        let gain = self.gain;
        for ch in pcm.iter_mut() {
            for s in ch.iter_mut() {
                // 限幅而不是回绕：*s * gain 会超过 1 的地方直接压到 0.999。
                *s = (*s * gain).clamp(-0.999_999, 0.999_999);
            }
        }
    }
}

/// 把整个 DSD 文件转成 planar f64 PCM。
pub fn decode_dsd_to_pcm(path: &std::path::Path) -> Result<(Vec<Vec<f64>>, u32), DsdConvertError> {
    let info: DsdInfo = crate::engine::dsd::parse(path).map_err(DsdConvertError::Dsd)?;
    let channels = info.channel_count();
    let mut reader = DsdReader::open(path).map_err(DsdConvertError::Dsd)?;
    let mut conv = DsdToPcm::new(channels, info.sample_rate);
    let mut out: Vec<Vec<f64>> = vec![Vec::new(); channels];
    let mut buf = Vec::new();
    while reader.next_block(&mut buf).map_err(DsdConvertError::Dsd)? {
        if buf.is_empty() {
            continue;
        }
        conv.push_bytes(&buf, info.lsb_first, &mut out);
    }
    conv.flush(&mut out);
    conv.set_gain(DSD_SACD_GAIN);
    conv.apply_gain(&mut out);
    Ok((out, conv.output_rate()))
}

/// DSD 转换错误。
#[derive(Debug)]
pub enum DsdConvertError {
    Dsd(crate::engine::dsd::DsdError),
}

impl std::fmt::Display for DsdConvertError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DsdConvertError::Dsd(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for DsdConvertError {}

// ---------------------------------------------------------------- DoP

/// DoP 标志字节（逐帧交替）。
pub const DOP_MARKER_A: u8 = 0x05;
pub const DOP_MARKER_B: u8 = 0xFA;

/// DoP 编码器：把字节交织的 DSD 装成 24 位 LE PCM。
///
/// 一帧消耗 `2 × 声道数` 字节 DSD（每声道 16 bit），产出 `3 × 声道数` 字节
/// （每声道 24 位小端：低字节、高字节、标志）。
pub struct DsdToDoP {
    channels: usize,
    lsb_first: bool,
    frame_count: u64,
    /// 上一块残留的不完整帧（跨块续上，保证与分块方式无关）。
    reste: Vec<u8>,
}

impl DsdToDoP {
    pub fn new(channels: usize, lsb_first: bool) -> Self {
        Self {
            channels,
            lsb_first,
            frame_count: 0,
            reste: Vec::new(),
        }
    }

    /// DoP 采样率 = DSD 率 / 16。
    pub fn dop_rate(dsd_rate: u32) -> u32 {
        dsd_rate / 16
    }

    /// 喂一段 DSD 字节，返回 24 位 LE 的 DoP PCM 字节。
    pub fn feed(&mut self, data: &[u8]) -> Vec<u8> {
        if self.channels == 0 {
            return Vec::new();
        }
        let mut tmp = std::mem::take(&mut self.reste);
        tmp.extend_from_slice(data);
        let bytes_per_frame = 2 * self.channels;
        let frames = tmp.len() / bytes_per_frame;
        let mut out = Vec::with_capacity(frames * 3 * self.channels);
        for f in 0..frames {
            let marker = if self.frame_count.is_multiple_of(2) {
                DOP_MARKER_A
            } else {
                DOP_MARKER_B
            };
            for ch in 0..self.channels {
                let b0 = tmp[f * bytes_per_frame + ch];
                let b1 = tmp[f * bytes_per_frame + ch + self.channels];
                // DoP 约定 MSB first；DSF 是 LSB first，要翻。
                let (d0, d1) = if self.lsb_first {
                    (crate::engine::dsd::reverse_bits(b0), crate::engine::dsd::reverse_bits(b1))
                } else {
                    (b0, b1)
                };
                out.push(d1); // 24 位 LE：字节 0
                out.push(d0); // 字节 1
                out.push(marker); // 字节 2
            }
            self.frame_count += 1;
        }
        self.reste.clear();
        self.reste.extend_from_slice(&tmp[frames * bytes_per_frame..]);
        out
    }
}

/// DoP 会不会被这条输出路径毁掉。
///
/// * `resampled`：输出采样率 ≠ DoP 采样率（重采样会重写标志字节）
/// * `channels_changed`：声道数变了（DoP 要求多声道同帧同标志）
///
/// 返回 `None` 表示"无需拒绝"：非 DoP 流，或 DoP 原样直出。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DopBreak {
    Resampled,
    ChannelsChanged,
}

/// DoP 在给定路径下是否仍然成立（`dop=false` 一律放行，PCM 不受影响）。
pub fn dop_survives(
    dop: bool,
    source_rate: u32,
    output_rate: u32,
    source_channels: u16,
    output_channels: u16,
) -> Option<DopBreak> {
    if !dop {
        return None;
    }
    if source_rate != output_rate {
        return Some(DopBreak::Resampled);
    }
    if source_channels != output_channels {
        return Some(DopBreak::ChannelsChanged);
    }
    None
}



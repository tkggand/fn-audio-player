//! 64-bit PCM 核心（Audio §f64 内核）。
//!
//! 全链路的统一表示：**planar f64**（每声道一条 `Vec<f64>`，取值区间 [-1, 1]）。
//!
//! 为什么是 f64 而不是 f32：
//! - PEQ/GEQ/AutoEQ 串接多个 biquad 会有累积误差，f32 在 24bit 素材上做深
//!   提升/衰减时量化噪声会明显抬高；
//! - ReplayGain 增益峰值封顶与真峰值估算需要比 f32 更多的有效位；
//! - f64 状态让同一份 DSP 代码能直接吃 32-bit float 源（DSD 转 PCM、升采样中间态）。
//!
//! 位深信息由容器/解码器给出，**不在解码阶段丢弃**：Hi-Res PCM 要求 24/32-bit
//! 一路保留到编码端（`BitDepth`）。

use std::cell::Cell;

/// planar 多声道缓冲：外层是声道，内层是采样。
pub type Planar = Vec<Vec<f64>>;

/// 受支持的整数位深（FLAC/WAV 容器）。
pub const SUPPORTED_INT_DEPTHS: [u32; 3] = [16, 24, 32];

/// 32-bit float 采样的"伪位深"，用于标记不可量化到整数的路径。
pub const FLOAT_DEPTH: u32 = 32;

/// 把源位深规整到容器可表达的位深（向上取整到 16/24/32）。
///
/// 与 Tune 的 `container_bit_depth` 同思路：FLAC 只认 8/16/24，WAV 整数认
/// 16/24/32，浮点源统一记 32（走 f32 WAV）。
pub fn container_bit_depth(src: Option<u32>) -> u32 {
    match src {
        None => 16,
        Some(b) if b <= 16 => 16,
        Some(b) if b <= 24 => 24,
        Some(_) => 32,
    }
}

/// Hi-Res 判定：位深或采样率超出 CD（16bit/44.1kHz）规格。
pub fn is_hires(bit_depth: u32, sample_rate: u32) -> bool {
    bit_depth > 16 || sample_rate > 48_000
}

/// Hi-Res 徽章文本（Web/App 直接显示）。
pub fn hires_badge(bit_depth: u32, sample_rate: u32, codec: &str) -> String {
    let base = format!("{} · {} Hz", codec.to_uppercase(), sample_rate);
    if is_hires(bit_depth, sample_rate) {
        format!("{base} · {bit_depth}bit")
    } else {
        base
    }
}

// ---------------- 构造与转换 ----------------

/// symphonia 的 f32 交错 → planar f64。
pub fn interleaved_f32_to_planar_f64(interleaved: &[f32], channels: usize) -> Planar {
    if channels == 0 {
        return Vec::new();
    }
    let mut planar: Planar = vec![Vec::with_capacity(interleaved.len() / channels); channels];
    for (i, s) in interleaved.iter().enumerate() {
        planar[i % channels].push(*s as f64);
    }
    planar
}

/// planar f64 → f32 交错（WebSocket 传输与浏览器 AudioBuffer 的边界）。
pub fn planar_f64_to_interleaved_f32(planar: &Planar) -> Vec<f32> {
    let channels = planar.len();
    if channels == 0 {
        return Vec::new();
    }
    let frames = planar[0].len();
    let mut out = Vec::with_capacity(frames * channels);
    for i in 0..frames {
        for ch in planar {
            out.push(ch[i] as f32);
        }
    }
    out
}

/// 声道对齐（幂等）：单声道复制为立体声；多声道（>2）只保留前两声道；空则补齐。
///
/// **只依据实际缓冲长度**判断——调用点会先后调���（解码后一次、准备重采样再一次），
/// 若按声明声道数重复补齐，立体声会被推成 3 声道。
pub fn align_channels(planar: &mut Planar) {
    match planar.len() {
        0 => {}
        1 => {
            let mono = planar[0].clone();
            planar.push(mono);
        }
        2 => {}
        _ => planar.truncate(2),
    }
}

#[inline]
pub fn frames(planar: &Planar) -> usize {
    planar.first().map(|c| c.len()).unwrap_or(0)
}

#[inline]
pub fn channels(planar: &Planar) -> usize {
    planar.len()
}

// ---------------- 电平与增益 ----------------

/// 采样峰值（绝对值最大）。
pub fn peak(planar: &Planar) -> f64 {
    planar
        .iter()
        .flat_map(|ch| ch.iter())
        .fold(0.0f64, |m, s| m.max(s.abs()))
}

/// 全部样本统一乘线性增益并夹到 [-1, 1]（就地）。
pub fn apply_gain(planar: &mut Planar, gain: f64) {
    if (gain - 1.0).abs() < 1e-12 || !gain.is_finite() || gain <= 0.0 {
        return;
    }
    for ch in planar.iter_mut() {
        for s in ch.iter_mut() {
            *s = (*s * gain).clamp(-1.0, 1.0);
        }
    }
}

/// 整体增益到峰值不超过 `ceiling`（线性幅度），防削波封顶。
///
/// 返回实际使用的增益倍数。`ceiling <= 0` 视为不限制。
pub fn apply_gain_with_ceiling(planar: &mut Planar, gain: f64, ceiling: f64) -> f64 {
    if gain <= 0.0 || !gain.is_finite() {
        return 1.0;
    }
    let mut g = gain;
    if ceiling > 0.0 {
        let pk = peak(planar);
        if pk > 0.0 {
            g = g.min(ceiling / pk);
        }
    }
    apply_gain(planar, g);
    g
}

/// 静音（就地）。
pub fn silence(planar: &mut Planar) {
    for ch in planar.iter_mut() {
        ch.iter_mut().for_each(|s| *s = 0.0);
    }
}

// ---------------- 量化（含 TPDF 抖动） ----------------

/// 确定性 PRNG（xorshift64*），抖动必须可复现以便测试与 A/B 对照。
#[inline]
fn next_rand(state: &mut u64) -> f64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    // 映射到 [-1, 1)。
    let v = (x.wrapping_mul(0x2545F4914F6CDD1D) >> 11) as f64 / (1u64 << 53) as f64;
    v * 2.0 - 1.0
}

/// 由内容派生的种子：同一首歌每次处理结果一致，便于回归对照。
pub fn seed_for(song_id: i64, channels: usize) -> u64 {
    let mut x = (song_id as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (channels as u64);
    x ^= x >> 30;
    x = x.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    x ^= x >> 27;
    x = x.wrapping_mul(0x94D0_49BB_1331_11EB);
    x ^= x >> 31;
    x | 1
}

/// 是否需要加抖动：位深收窄（量化误差不可闻被掩盖）或增益非 1 时。
fn should_dither(target_bits: u32, source_bits: u32, gain_changed: bool) -> bool {
    target_bits < source_bits || gain_changed
}

/// 抖动机：TPDF（两个独立均匀分布之和），幅度 ±1 LSB。
///
/// 只在**位深收窄**或增益非 1 时工作；位深不变且增益为 1 时完全旁路（`lsb == 0`）。
pub struct Dither {
    state: Cell<u64>,
    lsb: f64,
    target_bits: u32,
}

impl Dither {
    /// `source_bits`/`target_bits` 为源与目标位深；`gain_changed` 表示链路里做过增益。
    pub fn new(target_bits: u32, source_bits: u32, gain_changed: bool, seed: u64) -> Self {
        let bits = target_bits.clamp(1, 32);
        let lsb = if should_dither(bits, source_bits, gain_changed) {
            1.0 / ((1i64 << (bits - 1).min(31)) as f64)
        } else {
            0.0
        };
        Self {
            state: Cell::new(seed | 1),
            lsb,
            target_bits: bits,
        }
    }

    pub fn disabled() -> Self {
        Self {
            state: Cell::new(1),
            lsb: 0.0,
            target_bits: 16,
        }
    }

    pub fn is_active(&self) -> bool {
        self.lsb > 0.0
    }

    pub fn target_bits(&self) -> u32 {
        self.target_bits
    }

    /// 量化单个样本，返回**未左对齐**的整数域取值。
    #[inline]
    pub fn quantize(&self, sample: f64) -> i32 {
        let scale = ((1i64 << (self.target_bits - 1).min(31)) as f64) - 1.0;
        let v = sample.clamp(-1.0, 1.0);
        if self.lsb == 0.0 {
            return (v * scale).round() as i32;
        }
        // TPDF：均匀分布之和，幅度 ±1 LSB。
        let mut s = self.state.get();
        let d = (next_rand(&mut s) + next_rand(&mut s)) * self.lsb;
        self.state.set(s);
        ((v + d).clamp(-1.0, 1.0) * scale).round() as i32
    }

    /// 整段量化（planar 输入，**帧间交错**输出）。
    ///
    /// 交错顺序是硬要求：flacenc 的 `MemSource` 与 hound 的 `WavWriter` 都按
    /// “每帧逐声道”消费样本。若按声道顺序连续写（L 全部 + R 全部），立体声会被
    /// 当成两段独立内容——听起来就是 2 倍速、且只有左声道的前半段。
    pub fn quantize_planar(&self, planar: &Planar) -> Vec<i32> {
        let frames = frames(planar);
        let mut out = Vec::with_capacity(frames * channels(planar));
        for i in 0..frames {
            for ch in planar {
                out.push(self.quantize(*ch.get(i).unwrap_or(&0.0)));
            }
        }
        out
    }
}

/// 量化到 `bits` 位整数域（无抖动），返回未左对齐取值。
#[inline]
pub fn quantize_static(sample: f64, bits: u32) -> i32 {
    let scale = ((1i64 << (bits.clamp(1, 32) - 1).min(31)) as f64) - 1.0;
    (sample.clamp(-1.0, 1.0) * scale).round() as i32
}

/// planar f64 → 目标位深整数域（**右对齐**，flacenc / hound 都会自行按位宽收窄）。
///
/// FLAC 的 `MemSource` 与 hound 的 `WavWriter<i32>` 都要求取值落在目标位宽范围内，
/// 超出范围会直接报 `VerifyError` / `TooManyBits`。
pub fn quantize_planar_i32(
    planar: &Planar,
    target_bits: u32,
    source_bits: u32,
    gain_changed: bool,
    seed: u64,
) -> Vec<i32> {
    let dither = Dither::new(target_bits, source_bits, gain_changed, seed);
    dither.quantize_planar(planar)
}

/// planar f64 → f32 交错（32-bit float WAV 用）。
pub fn planar_to_interleaved_f32_bytes(planar: &Planar) -> Vec<u8> {
    let frames = frames(planar);
    let mut bytes = Vec::with_capacity(frames * channels(planar) * 4);
    for i in 0..frames {
        for ch in planar {
            bytes.extend_from_slice(&(*ch.get(i).unwrap_or(&0.0) as f32).to_le_bytes());
        }
    }
    bytes
}

// ---------------- 重采样 ----------------

/// planar f64 重采样到任意目标采样率（rubato FFT 同步重采样，自动裁剪启动延迟）。
///
/// 采样率相同则原样返回（零成本直通，不引入任何误差）。
pub fn resample(planar: Planar, from: u32, to: u32) -> anyhow::Result<Planar> {
    if from == to || planar.is_empty() {
        return Ok(planar);
    }
    use rubato::audioadapter_buffers::owned::InterleavedOwned;
    use rubato::{Fft, FixedSync, Resampler};

    const CHUNK: usize = 1024;
    let ch = planar.len();
    let n = frames(&planar);
    if n == 0 {
        return Ok(planar);
    }

    // planar f64 → 交错。
    let mut interleaved: Vec<f64> = Vec::with_capacity(n * ch);
    for i in 0..n {
        for c in &planar {
            interleaved.push(c[i]);
        }
    }

    let input = InterleavedOwned::new_from(interleaved, ch, n)?;
    let mut resampler = Fft::<f64>::new(
        from as usize,
        to as usize,
        CHUNK,
        ch,
        FixedSync::Both,
    )?;
    let output = resampler.process_all(&input, n, None)?;
    let out = output.take_data();

    // 交错 → planar。
    let out_frames = out.len() / ch;
    let mut planar_out: Planar = vec![Vec::with_capacity(out_frames); ch];
    for c in 0..ch {
        planar_out[c].extend(out[c..].iter().step_by(ch).copied());
    }
    Ok(planar_out)
}

/// 重采样到指定采样率（保持声道布局）。
pub fn resample_to_rate(planar: Planar, from: u32, to: u32) -> anyhow::Result<Planar> {
    resample(planar, from, to)
}



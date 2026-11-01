//! 输出端频谱分析：对齐 Web 端 `Spectrum.tsx` 的 28 段柱状频谱。
//!
//! Web 侧取 `analyser.getByteFrequencyData()`（fftSize 128 → 64 根 bin，只用前
//! 70%），第 `i` 根柱子对应 `floor(i / bars * 0.7 * 64)` 号 bin；数值是 dBFS
//! 在 -90 ~ -10 dB 之间的线性映射（0..255），并带 0.8 的平滑。
//!
//! 这里不做整段 FFT：对每根柱子的中心频率做一次 Goertzel（1024 点窗 + Hann），
//! 28 × 1024 次乘加约每 512 个输出帧算一次（48 kHz 下约 93 次/秒），开销远低于
//! 重采样，放在输出回调里也不会挤占缓冲预算。

use std::f64::consts::PI;

/// 分析窗长度（样本）。
const WINDOW: usize = 1024;
/// 频谱柱数量（与 Web 端 `Spectrum bars={28}` 一致）。
pub const BARS: usize = 28;
/// Web 端 fftSize = 128，取 70% 的 bin。
const BIN_COUNT_70: f64 = 64.0 * 0.7;
/// Web Audio 默认 `smoothingTimeConstant`。
const SMOOTH: f32 = 0.8;

pub struct SpectrumAnalyzer {
    /// 环形缓冲（单声道样本）。
    buf: Vec<f32>,
    pos: usize,
    filled: usize,
    since_compute: usize,
    /// Hann 窗（节省每次计算时的三角函数）。
    window: Vec<f64>,
    window_sum: f64,
    /// 每根柱子的输出（0.0–1.0）。
    out: Vec<f32>,
}

impl SpectrumAnalyzer {
    pub fn new() -> Self {
        let window: Vec<f64> = (0..WINDOW)
            .map(|i| 0.5 - 0.5 * (2.0 * PI * i as f64 / (WINDOW - 1) as f64).cos())
            .collect();
        let window_sum: f64 = window.iter().sum();
        Self {
            buf: vec![0.0; WINDOW],
            pos: 0,
            filled: 0,
            since_compute: 0,
            window,
            window_sum,
            out: vec![0.0; BARS],
        }
    }

    /// 换曲/停止时清零（新歌从静止开始，不残留上一首的柱子）。
    pub fn reset(&mut self) {
        self.buf.iter_mut().for_each(|v| *v = 0.0);
        self.pos = 0;
        self.filled = 0;
        self.since_compute = 0;
        self.out.iter_mut().for_each(|v| *v = 0.0);
    }

    /// 喂入一帧立体声样本（已在调用方做音量与 DSP）。
    pub fn push(&mut self, l: f32, r: f32, rate: u32) {
        self.buf[self.pos] = (l + r) * 0.5;
        self.pos = (self.pos + 1) % WINDOW;
        if self.filled < WINDOW {
            self.filled += 1;
        }
        self.since_compute += 1;
        if self.filled >= WINDOW && self.since_compute >= WINDOW / 2 {
            self.since_compute = 0;
            self.compute(rate);
        }
    }

    pub fn values(&self) -> &[f32] {
        &self.out
    }

    fn compute(&mut self, rate: u32) {
        if rate == 0 {
            return;
        }
        let rate = rate as f64;
        let start = self.pos; // 环形缓冲里最旧样本的位置
        let buf = &self.buf;
        let window = &self.window;
        let sum = self.window_sum;
        let bars = self.out.len();

        for (b, slot) in self.out.iter_mut().enumerate() {
            // 与 Web 端同样的线性分桶：bar → bin → 频率。
            let bin = (b as f64 / bars as f64 * BIN_COUNT_70).floor();
            let freq = bin * rate / 128.0;
            let coeff = 2.0 * (2.0 * PI * freq / rate).cos();

            let mut s1 = 0.0f64;
            let mut s2 = 0.0f64;
            let mut idx = start;
            for i in 0..WINDOW {
                let x = buf[idx] as f64 * window[i];
                idx += 1;
                if idx == WINDOW {
                    idx = 0;
                }
                let s0 = x + coeff * s1 - s2;
                s2 = s1;
                s1 = s0;
            }
            let power = (s1 * s1 + s2 * s2 - coeff * s1 * s2).max(0.0);
            let mag = 2.0 * power.sqrt() / sum;
            // dBFS → 0..1（-90 dB 为底，-10 dB 为顶，与 Web AnalyserNode 一致）。
            let db = 20.0 * mag.max(1e-9).log10();
            let v = ((db + 90.0) / 80.0).clamp(0.0, 1.0) as f32;
            *slot = *slot * SMOOTH + v * (1.0 - SMOOTH);
        }
    }
}

impl Default for SpectrumAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

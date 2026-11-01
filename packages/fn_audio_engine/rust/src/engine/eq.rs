//! 参数均衡器（PEQ）与图形均衡器（GEQ）内核 —— f64 全精度。
//!
//! - **PEQ**：任意数量的频段，每段含频率 / 增益 / Q / 类型 / 可选声道。
//! - **GEQ**：本质是"频率栅格固定、类型固定为 peak"的 PEQ（见 `geq` 模块），
//!   与 Tune 的做法一致——不维护两套引擎。
//! - **自动预留 headroom**：按级联冲激响应的 L1 范数反推最大无损增益，
//!   这样"拉满 +12dB 低频"不会立刻削顶；用户也可手动覆盖 preamp。
//!
//! 配置 JSON（`/api/dsp/eq` 读写，Web/App 共用）：
//!
//! ```json
//! {
//!   "enabled": true,
//!   "preamp_db": null,          // null = 自动
//!   "headroom": "safe",         // safe | manual
//!   "bands": [
//!     {"freq": 105, "gain": 6.4, "q": 0.7, "type": "low_shelf"},
//!     {"freq": 8800, "gain": 5.1, "q": 1.42, "type": "peak", "channel": null}
//!   ]
//! }
//! ```

use serde::{Deserialize, Serialize};

use crate::engine::pcm::Planar;

/// 滤波器类型（RBJ Audio EQ Cookbook）。
///
/// 反序列化刻意宽松：AutoEq 导出用 `PK` / `LS` / `HSC` 等缩写，Cadence/Reverb
/// 用 `lowshelf` 等驼峰写法，全部映射到同一组变体，未知值退化为 `peak`。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum BandType {
    #[default]
    Peak,
    LowShelf,
    HighShelf,
    LowPass,
    HighPass,
    Notch,
    BandPass,
    AllPass,
}

impl<'de> Deserialize<'de> for BandType {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(BandType::parse(&s))
    }
}

impl BandType {
    /// 宽容解析：未知类型按 peak 处理（AutoEq 导出里常见变体）。
    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "low_shelf" | "lowshelf" | "ls" | "lsc" | "lsq" => BandType::LowShelf,
            "high_shelf" | "highshelf" | "hs" | "hsc" | "hsq" => BandType::HighShelf,
            "low_pass" | "lowpass" | "lp" | "lpq" => BandType::LowPass,
            "high_pass" | "highpass" | "hp" | "hpq" => BandType::HighPass,
            "notch" | "no" => BandType::Notch,
            "band_pass" | "bandpass" | "bp" => BandType::BandPass,
            "all_pass" | "allpass" | "ap" => BandType::AllPass,
            _ => BandType::Peak,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            BandType::Peak => "peak",
            BandType::LowShelf => "low_shelf",
            BandType::HighShelf => "high_shelf",
            BandType::LowPass => "low_pass",
            BandType::HighPass => "high_pass",
            BandType::Notch => "notch",
            BandType::BandPass => "band_pass",
            BandType::AllPass => "all_pass",
        }
    }

    /// 该类型是否受 gain 影响（peak/shelf 用 gain，pass 类不用）。
    pub fn uses_gain(&self) -> bool {
        matches!(
            self,
            BandType::Peak
                | BandType::LowShelf
                | BandType::HighShelf
                | BandType::BandPass
                | BandType::Notch
                | BandType::AllPass
        )
    }
}

/// 单个频段。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EqBand {
    /// 中心频率 Hz（10 – 0.45×fs）
    #[serde(default = "default_freq")]
    pub freq: f64,
    /// 增益 dB（-24 – +24）
    #[serde(default)]
    pub gain: f64,
    /// 品质因数（0.1 – 30）
    #[serde(default = "default_q")]
    pub q: f64,
    /// 类型
    #[serde(rename = "type", default)]
    pub band_type: BandType,
    /// None = 双声道同时；Some(0)=左，Some(1)=右
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel: Option<u16>,
}

fn default_freq() -> f64 {
    1000.0
}
fn default_q() -> f64 {
    1.0
}

impl Default for EqBand {
    fn default() -> Self {
        Self {
            freq: default_freq(),
            gain: 0.0,
            q: default_q(),
            band_type: BandType::Peak,
            channel: None,
        }
    }
}

impl EqBand {
    pub fn peak(freq: f64, gain_db: f64, q: f64) -> Self {
        Self {
            freq,
            gain: gain_db,
            q,
            ..Default::default()
        }
    }

    pub fn shelf_low(freq: f64, gain_db: f64, q: f64) -> Self {
        Self {
            freq,
            gain: gain_db,
            q,
            band_type: BandType::LowShelf,
            channel: None,
        }
    }

    pub fn shelf_high(freq: f64, gain_db: f64, q: f64) -> Self {
        Self {
            freq,
            gain: gain_db,
            q,
            band_type: BandType::HighShelf,
            channel: None,
        }
    }

    /// 该频段是否中性（增益为 0 的 peak/shelf；pass 类永远不中性）。
    pub fn is_neutral(&self) -> bool {
        match self.band_type {
            BandType::Peak | BandType::LowShelf | BandType::HighShelf => self.gain.abs() < 0.01,
            _ => false,
        }
    }

    /// 归一化到合法域（频率不超过 0.45×fs，Q 0.1–30，增益 ±24）。
    pub fn normalized(&self, sample_rate: u32) -> Self {
        let fs = sample_rate as f64;
        let nyq = fs * 0.45;
        let mut b = self.clone();
        b.freq = self.freq.clamp(10.0, nyq.max(10.0));
        b.q = if self.q.is_finite() && self.q > 0.0 {
            self.q.clamp(0.1, 30.0)
        } else {
            1.0
        };
        if b.gain.is_finite() {
            b.gain = b.gain.clamp(-24.0, 24.0);
        } else {
            b.gain = 0.0;
        }
        b
    }
}

/// Headroom 策略。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Headroom {
    /// 按级联 L1 范数自动预留（不会削顶）
    #[default]
    Safe,
    /// 使用用户指定的 preamp_db
    Manual,
}

/// EQ 配置档。
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct EqProfile {
    #[serde(default)]
    pub enabled: bool,
    /// 手动 preamp（dB）；`headroom=manual` 时生效。
    #[serde(default)]
    pub preamp_db: Option<f64>,
    #[serde(default)]
    pub headroom: Headroom,
    #[serde(default)]
    pub bands: Vec<EqBand>,
    /// AutoEq 导入时原始文本里的 Preamp 值（仅展示用，不参与计算）。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autoeq_preamp_db: Option<f64>,
    /// 来源标记：manual / autoeq / geq
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

impl EqProfile {
    /// 解析 JSON 配置。
    pub fn from_json(json: &str) -> anyhow::Result<Self> {
        let p: EqProfile = serde_json::from_str(json)?;
        Ok(p.sanitized())
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".into())
    }

    /// 过滤非法频段、限制数量（对齐 AutoEq 上限 31 段，防手滑发 500 段）。
    pub fn sanitized(&self) -> Self {
        const MAX_BANDS: usize = 31;
        let mut p = self.clone();
        p.bands.truncate(MAX_BANDS);
        p.bands.retain(|b| b.freq.is_finite() && b.freq > 0.0);
        // 不要在这里「有非中性频段就自动 enabled」：用户手动关闭（PUT enabled=false /
        // DELETE /eq 清空配置）后再读配置会被强行打开，表现为关闭无效、EQ 一直生效。
        p
    }

    /// 是否会产生实际变化（用于判断要不要跑 DSP）。
    pub fn is_active(&self) -> bool {
        self.enabled && self.bands.iter().any(|b| !b.is_neutral())
    }

    /// 生效频段数（跳过中性段）。
    pub fn active_band_count(&self) -> usize {
        self.bands
            .iter()
            .filter(|b| !b.is_neutral())
            .count()
    }

    /// 声道最大索引 + 1（None 视为双声道）。
    fn channel_span(&self) -> usize {
        self.bands
            .iter()
            .filter_map(|b| b.channel)
            .max()
            .map(|m| m as usize + 1)
            .unwrap_or(2)
            .max(2)
    }
}

/// 双二阶系数（a0 归一化为 1）。
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Biquad {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl Biquad {
    pub const PASSTHROUGH: Self = Self {
        b0: 1.0,
        b1: 0.0,
        b2: 0.0,
        a1: 0.0,
        a2: 0.0,
    };

    /// 直接 I 型（DF-I）单样本处理，f64 状态。
    #[inline]
    pub fn step(&self, s: &mut BiquadState, x: f64) -> f64 {
        let y = self.b0 * x + self.b1 * s.x1 + self.b2 * s.x2 - self.a1 * s.y1 - self.a2 * s.y2;
        s.x2 = s.x1;
        s.x1 = x;
        s.y2 = s.y1;
        s.y1 = y;
        y
    }

    /// 在 `freq_hz` 处的幅度响应（dB）。
    pub fn magnitude_db(&self, freq_hz: f64, sample_rate: u32) -> f64 {
        let w = 2.0 * std::f64::consts::PI * freq_hz / sample_rate as f64;
        let (sin_w, cos_w) = w.sin_cos();
        let cos_2w = 2.0 * cos_w * cos_w - 1.0;
        let sin_2w = 2.0 * sin_w * cos_w;
        let num_re = self.b0 + self.b1 * cos_w + self.b2 * cos_2w;
        let num_im = -(self.b1 * sin_w + self.b2 * sin_2w);
        let den_re = 1.0 + self.a1 * cos_w + self.a2 * cos_2w;
        let den_im = -(self.a1 * sin_w + self.a2 * sin_2w);
        let num = (num_re * num_re + num_im * num_im).sqrt();
        let den = (den_re * den_re + den_im * den_im).sqrt();
        if den <= 0.0 || num <= 0.0 {
            return 0.0;
        }
        20.0 * (num / den).log10()
    }
}

/// 双二阶状态。
#[derive(Debug, Clone, Copy, Default)]
pub struct BiquadState {
    pub x1: f64,
    pub x2: f64,
    pub y1: f64,
    pub y2: f64,
}

/// 架式滤波器（LowShelf / HighShelf）——RBJ Audio EQ Cookbook 系数表。
///
/// 单独成函数的原因：`eq`（PEQ/GEQ）与 `dsp_builtin`（CamillaDSP 预设）两条
/// 路径都要架式，之前是两份几乎相同的拷贝。表本身是业界通用写法，端点行为
/// 为：低架 DC=G / 高频 0dB，高架 DC=0dB / Nyquist=G。
pub fn design_shelf(high: bool, gain_db: f64, q: f64, freq: f64, sample_rate: u32) -> Biquad {
    let fs = sample_rate as f64;
    let f0 = freq.clamp(10.0, fs * 0.45);
    let w0 = 2.0 * std::f64::consts::PI * f0 / fs;
    let (sin_w, cos_w) = w0.sin_cos();
    let alpha = sin_w / (2.0 * if q.is_finite() && q > 0.0 { q } else { 0.707 });
    let a = 10f64.powf(gain_db / 40.0);
    let sqrt_a = a.sqrt();

    let (b0, b1, b2, a0, a1, a2) = if high {
        (
            a * ((a + 1.0) + (a - 1.0) * cos_w + 2.0 * sqrt_a * alpha),
            -2.0 * a * ((a - 1.0) + (a + 1.0) * cos_w),
            a * ((a + 1.0) + (a - 1.0) * cos_w - 2.0 * sqrt_a * alpha),
            (a + 1.0) - (a - 1.0) * cos_w + 2.0 * sqrt_a * alpha,
            2.0 * ((a - 1.0) - (a + 1.0) * cos_w),
            (a + 1.0) - (a - 1.0) * cos_w - 2.0 * sqrt_a * alpha,
        )
    } else {
        (
            a * ((a + 1.0) - (a - 1.0) * cos_w + 2.0 * sqrt_a * alpha),
            2.0 * a * ((a - 1.0) - (a + 1.0) * cos_w),
            a * ((a + 1.0) - (a - 1.0) * cos_w - 2.0 * sqrt_a * alpha),
            (a + 1.0) + (a - 1.0) * cos_w + 2.0 * sqrt_a * alpha,
            -2.0 * ((a - 1.0) + (a + 1.0) * cos_w),
            (a + 1.0) + (a - 1.0) * cos_w - 2.0 * sqrt_a * alpha,
        )
    };

    if a0.abs() < 1e-18 {
        return Biquad::PASSTHROUGH;
    }
    Biquad {
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: a1 / a0,
        a2: a2 / a0,
    }
}

/// RBJ Audio EQ Cookbook 系数设计。
pub fn design(band: &EqBand, sample_rate: u32) -> Biquad {
    let b = band.normalized(sample_rate);
    let fs = sample_rate as f64;
    let f0 = b.freq.clamp(10.0, fs * 0.45);
    let w0 = 2.0 * std::f64::consts::PI * f0 / fs;
    let (sin_w, cos_w) = w0.sin_cos();
    let alpha = sin_w / (2.0 * b.q);
    let a = 10f64.powf(b.gain / 40.0);

    // 架式走共享实现（见 design_shelf）。
    if matches!(b.band_type, BandType::LowShelf | BandType::HighShelf) {
        return design_shelf(b.band_type == BandType::HighShelf, b.gain, b.q, f0, sample_rate);
    }

    let (b0, b1, b2, a0, a1, a2) = match b.band_type {
        // 架式已在上面提前返回；这里只是让匹配穷尽（不会走到）。
        BandType::LowShelf | BandType::HighShelf => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
        BandType::LowPass => (
            (1.0 - cos_w) / 2.0,
            1.0 - cos_w,
            (1.0 - cos_w) / 2.0,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        BandType::HighPass => (
            (1.0 + cos_w) / 2.0,
            -(1.0 + cos_w),
            (1.0 + cos_w) / 2.0,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        // 架式在函数开头已提前返回，这里落到 _ 分支（直通）。
        BandType::BandPass => {
            // 常数 0dB 峰值增益（Q 决定带宽）。
            (
                alpha,
                0.0,
                -alpha,
                1.0 + alpha,
                -2.0 * cos_w,
                1.0 - alpha,
            )
        }
        BandType::Notch => (
            1.0,
            -2.0 * cos_w,
            1.0,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        BandType::AllPass => (
            1.0 - alpha,
            -2.0 * cos_w,
            1.0 + alpha,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        BandType::Peak => (
            1.0 + alpha * a,
            -2.0 * cos_w,
            1.0 - alpha * a,
            1.0 + alpha / a,
            -2.0 * cos_w,
            1.0 - alpha / a,
        ),
    };

    if a0.abs() < 1e-12 {
        return Biquad::PASSTHROUGH;
    }
    Biquad {
        b0: b0 / a0,
        b1: b1 / a0,
        b2: b2 / a0,
        a1: a1 / a0,
        a2: a2 / a0,
    }
}

/// EQ 处理器：每声道一条级联。
pub struct EqProcessor {
    /// `cascades[ch]` = 该声道的滤波器串。
    cascades: Vec<Vec<Biquad>>,
    states: Vec<Vec<BiquadState>>,
    preamp: f64,
    sample_rate: u32,
}

impl EqProcessor {
    pub fn new(profile: &EqProfile, sample_rate: u32, channels: usize) -> anyhow::Result<Self> {
        let profile = profile.sanitized();
        let ch = channels.max(profile.channel_span());
        let mut cascades = Vec::with_capacity(ch);
        for c in 0..ch {
            let mut cascade = Vec::new();
            for band in &profile.bands {
                if band.is_neutral() {
                    continue;
                }
                match band.channel {
                    Some(idx) if idx as usize != c => continue,
                    _ => {}
                }
                cascade.push(design(band, sample_rate));
            }
            cascades.push(cascade);
        }
        let states = vec![vec![BiquadState::default(); cascades[0].len()]; ch];
        let preamp = resolve_preamp(&profile, &cascades);
        Ok(Self {
            cascades,
            states,
            preamp,
            sample_rate,
        })
    }

    /// 实际使用的 preamp 增益倍数。
    pub fn preamp_gain(&self) -> f64 {
        self.preamp
    }

    /// 实际使用的 preamp（dB）。
    pub fn preamp_db(&self) -> f64 {
        if self.preamp <= 0.0 {
            return 0.0;
        }
        20.0 * self.preamp.log10()
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    /// 清空状态（换曲/热切换时调用）。
    pub fn reset(&mut self) {
        for st in self.states.iter_mut() {
            st.fill(BiquadState::default());
        }
    }

    /// 原地处理 planar 缓冲（先 preamp 一次，再级联）。
    ///
    /// 注意：preamp **每个声道只乘一次**——早前误写在 biquad 循环内部，
    /// N 段频段就把预留乘了 N 次（3 段时额外衰减 18dB，听感是"EQ 一开就没声了"）。
    pub fn process(&mut self, buffers: &mut Planar) {
        if self.preamp != 1.0 {
            for ch in buffers.iter_mut() {
                for s in ch.iter_mut() {
                    *s *= self.preamp;
                }
            }
        }
        for (ci, ch) in buffers.iter_mut().enumerate() {
            let Some(cascade) = self.cascades.get(ci) else {
                continue;
            };
            if cascade.is_empty() {
                continue;
            }
            let states = &mut self.states[ci];
            for (bi, coef) in cascade.iter().enumerate() {
                let st = &mut states[bi];
                for s in ch.iter_mut() {
                    *s = coef.step(st, *s);
                }
            }
        }
    }

    /// 频响曲线（用于 Web 绘图）：返回 (频率Hz, dB) 点序列，含 preamp。
    pub fn response(&self, points: usize, f_min: f64, f_max: f64) -> Vec<(f64, f64)> {
        let nyq = self.sample_rate as f64 / 2.0;
        let f_max = f_max.min(nyq * 0.98);
        let preamp_db = 20.0 * self.preamp.max(1e-12).log10();
        (0..points)
            .map(|i| {
                let t = i as f64 / (points.saturating_sub(1).max(1)) as f64;
                // 对数频率轴（听感更均匀）。
                let f = f_min * (f_max / f_min).powf(t);
                let mut db = preamp_db;
                if let Some(c0) = self.cascades.first() {
                    for coef in c0 {
                        db += coef.magnitude_db(f, self.sample_rate);
                    }
                }
                (f, db)
            })
            .collect()
    }
}

/// 计算实际 preamp 增益倍数。
///
/// `Safe`：预留**级联的最大频响 + 余量**——最大频响才是"不削顶"的数学边界。
/// 早期版本用冲激响应 L1 范数，对高 Q 谐振会把长长的振铃尾巴也计入，
/// 单个 +6dB peak(Q=1) 竟被压掉 7.2dB（实测），完全不可用。
/// `Manual`：用用户给的 dB。
fn resolve_preamp(profile: &EqProfile, cascades: &[Vec<Biquad>]) -> f64 {
    if profile.headroom == Headroom::Manual {
        let db = profile.preamp_db.unwrap_or(0.0).clamp(-24.0, 24.0);
        return 10f64.powf(db / 20.0);
    }
    // 空级联（平直曲线）必须严格 1.0——否则会被预留 margin 无故压低。
    if cascades.iter().all(|c| c.is_empty()) {
        return 1.0;
    }
    let worst_db = cascades
        .iter()
        .map(|c| max_response_db(c, HEADROOM_SAMPLE_RATE))
        .fold(0.0f64, f64::max);
    let headroom_db = -(worst_db + HEADROOM_MARGIN_DB);
    if headroom_db >= 0.0 || !headroom_db.is_finite() {
        return 1.0;
    }
    10f64.powf(headroom_db / 20.0)
}

/// headroom 预留用的参考采样率（±1kHz 内最大频响差异 < 0.01dB，可忽略）。
const HEADROOM_SAMPLE_RATE: u32 = 48_000;
/// 额外安全余量 dB：覆盖滤波器过渡带与浮点误差。
const HEADROOM_MARGIN_DB: f64 = 0.3;

/// 级联的最大频响（dB），对数频率网格密集采样。
///
/// 这是稳态信号下"任何频率都不会超过的最大增益"，即 headroom 的正确依据。
pub fn max_response_db(cascade: &[Biquad], sample_rate: u32) -> f64 {
    if cascade.is_empty() {
        return 0.0;
    }
    const POINTS: usize = 2048;
    let f_max = sample_rate as f64 * 0.49;
    let mut worst = 0.0f64;
    for i in 0..POINTS {
        let t = i as f64 / (POINTS - 1) as f64;
        let f = 20.0 * (f_max / 20.0).powf(t);
        let db: f64 = cascade.iter().map(|c| c.magnitude_db(f, sample_rate)).sum();
        if db > worst {
            worst = db;
        }
    }
    worst
}

/// 单频点幅度（dB），便于测试与 UI 读数。
pub fn band_gain_db_at(band: &EqBand, freq_hz: f64, sample_rate: u32) -> f64 {
    design(band, sample_rate).magnitude_db(freq_hz, sample_rate)
}

/// 便捷构造：把若干频段包成启用状态。
pub fn profile_from_bands(bands: Vec<EqBand>) -> EqProfile {
    EqProfile {
        enabled: true,
        bands,
        ..Default::default()
    }
}



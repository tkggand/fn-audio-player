//! 交叉馈送（Crossfeed）：耳机上模拟双耳串音，把声像从"头内"推到"头前"。
//!
//! 算法移植自 tune-server-rust 的 `tune-plugin-crossfeed`（差分类、Mid 保留）。
//! 对每一帧立体声，取延迟 `delay_samples` 的干信号 `Ld`/`Rd`：
//!
//! ```text
//! L_out = L + amount * f(Rd - Ld)
//! R_out = R + amount * f(Ld - Rd)
//! ```
//!
//! 两个修正项互为相反数，所以 `L_out + R_out == L + R`：**中置（Mid）逐样本
//! 保留**，只重塑**边侧（Side）**——完全单声道的内容（L == R）原样通过，
//! 这一点不因头影滤波是否开启而改变。`f` 是可选的**头影低通**（默认关闭），
//! 只作用于交叉项：真实 HRTF 只在低频串音，高频被头颅遮挡。
//!
//! 只在 2 声道上生效；其他声道数是静默空操作（把 5.1 当成 L/R 对去混音会
//! 把不相干的声道搅在一起）。
//!
//! 与参考实现的一处差异：这里**不做 ±1 限幅**。FN-Audio 全链路是 f64、只在
//! 量化时饱和（`pcm::quantize`），中途限幅会引入非线性失真，也会破坏上面
//! "中置逐样本保留"的精确性。

use serde::{Deserialize, Serialize};
use std::f64::consts::PI;

use crate::engine::pcm::Planar;

/// 头影低通频率下限（Hz）。
pub const CUTOFF_MIN_HZ: f64 = 200.0;
/// 头影低通频率上限（Hz）。
pub const CUTOFF_MAX_HZ: f64 = 20_000.0;
/// 头影低通默认频率（Hz）。
pub const CUTOFF_DEFAULT_HZ: f64 = 700.0;
/// 头影低通坡度下限（dB/oct）。
pub const SLOPE_MIN_DB_OCT: f64 = 3.0;
/// 头影低通坡度上限（dB/oct），6 即一阶低通。
pub const SLOPE_MAX_DB_OCT: f64 = 6.0;
/// 头影低通默认坡度（dB/oct）。
pub const SLOPE_DEFAULT_DB_OCT: f64 = 6.0;
/// 交叉馈送强度上限：0.5 已是很"窄"的声像，再大就糊了。
pub const AMOUNT_MAX: f64 = 0.5;
/// 交叉路径延迟上限（毫秒）：生理性双耳延迟约 0.6~0.7 ms，几毫秒已远超有用范围。
pub const DELAY_MAX_MS: f64 = 5.0;

/// 交叉馈送配置（全局一份，存在 `system_config.crossfeed`）。
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct CrossfeedSettings {
    /// 总开关。
    pub enabled: bool,
    /// 交叉强度（0 ~ 0.5），0 = 直通。
    pub amount: f64,
    /// 交叉路径延迟（毫秒，0 ~ 5），0 = 瞬时。
    pub delay_ms: f64,
    /// 是否对交叉项施加头影低通。
    pub head_shadow_enabled: bool,
    /// 头影低通频率（Hz，200 ~ 20000）。
    pub cutoff_hz: f64,
    /// 头影低通坡度（dB/oct，3 ~ 6）。
    pub slope_db_per_octave: f64,
}

impl Default for CrossfeedSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            amount: 0.3,
            delay_ms: 0.3,
            head_shadow_enabled: false,
            cutoff_hz: CUTOFF_DEFAULT_HZ,
            slope_db_per_octave: SLOPE_DEFAULT_DB_OCT,
        }
    }
}

impl CrossfeedSettings {
    /// 越界即视为非法（HTTP 层挡下；这里只做兜底钳制）。NaN 回落到默认值。
    pub fn sanitized(self) -> Self {
        let d = Self::default();
        let clean = |v: f64, fallback: f64| if v.is_finite() { v } else { fallback };
        Self {
            enabled: self.enabled,
            amount: clean(self.amount, d.amount).clamp(0.0, AMOUNT_MAX),
            delay_ms: clean(self.delay_ms, d.delay_ms).clamp(0.0, DELAY_MAX_MS),
            head_shadow_enabled: self.head_shadow_enabled,
            cutoff_hz: clean(self.cutoff_hz, d.cutoff_hz).clamp(CUTOFF_MIN_HZ, CUTOFF_MAX_HZ),
            slope_db_per_octave: clean(self.slope_db_per_octave, d.slope_db_per_octave)
                .clamp(SLOPE_MIN_DB_OCT, SLOPE_MAX_DB_OCT),
        }
    }

    /// 是否会改变音频（开关关闭或强度为 0 都算关闭）。
    pub fn is_active(&self) -> bool {
        self.enabled && self.amount > 0.0
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str::<Self>(json).map(|s| s.sanitized())
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".into())
    }

    /// 头影滤波设置：关闭时为 `None`。
    fn shadow(&self) -> Option<ShadowSettings> {
        self.head_shadow_enabled.then_some(ShadowSettings {
            cutoff_hz: self.cutoff_hz,
            slope_db_per_octave: self.slope_db_per_octave,
        })
    }
}

/// 交叉馈送处理器（状态 = 两条延迟线 + 头影滤波状态）。
///
/// 延迟线跨 `process` 调用保留，因此分块处理（WS 会话）与整段处理
/// （`/api/stream` 流水线）共用同一套算法。
pub struct CrossfeedProcessor {
    amount: f64,
    delay_samples: usize,
    ring_l: Vec<f64>,
    ring_r: Vec<f64>,
    pos: usize,
    shadow: Option<ShadowFilter>,
}

impl CrossfeedProcessor {
    pub fn new(sample_rate: u32, settings: &CrossfeedSettings) -> Self {
        let s = settings.sanitized();
        let delay_samples = ms_to_samples(sample_rate, s.delay_ms);
        let shadow = s.shadow();
        Self {
            amount: if s.enabled { s.amount } else { 0.0 },
            delay_samples,
            ring_l: vec![0.0; delay_samples],
            ring_r: vec![0.0; delay_samples],
            pos: 0,
            shadow: shadow.map(|o| ShadowFilter::design(sample_rate, o)),
        }
    }

    /// 强度为 0：精确恒等，连延迟线状态都不需要推进。
    pub fn is_neutral(&self) -> bool {
        self.amount == 0.0
    }

    /// 延迟 `delay_samples` 的干样本对，并推进延迟线。
    #[inline]
    fn delay(&mut self, l: f64, r: f64) -> (f64, f64) {
        if self.delay_samples == 0 {
            return (l, r);
        }
        let d = (self.ring_l[self.pos], self.ring_r[self.pos]);
        // 先读延迟样本，再写入当前干样本。
        self.ring_l[self.pos] = l;
        self.ring_r[self.pos] = r;
        self.pos += 1;
        if self.pos >= self.delay_samples {
            self.pos = 0;
        }
        d
    }

    /// 对平面缓冲施加交叉馈送（原地）。非立体声为空操作。
    pub fn process(&mut self, planar: &mut Planar) {
        if self.is_neutral() || planar.len() != 2 {
            return;
        }
        let frames = planar[0].len().min(planar[1].len());
        if frames == 0 {
            return;
        }
        let (left_all, right_all) = planar.split_at_mut(1);
        let left = &mut left_all[0];
        let right = &mut right_all[0];
        for i in 0..frames {
            let l = left[i];
            let r = right[i];
            let (ld, rd) = self.delay(l, r);
            let diff = rd - ld;
            let filtered = match &mut self.shadow {
                Some(f) => f.process(diff),
                None => diff,
            };
            let c = self.amount * filtered;
            left[i] = l + c;
            right[i] = r - c;
        }
    }

    /// 实际生效的交叉延迟（样本数），供界面/诊断展示。
    pub fn delay_samples(&self) -> usize {
        self.delay_samples
    }

    /// 继承上一条延迟线（仅在长度相同时）。
    ///
    /// 交叉项建立在**延迟样本**上：新处理器若从零状态起步，交叉项会在
    /// `delay_samples` 个样本里塌成静音——那是一段不连续，也就是一声"咔"。
    /// 拖动强度滑杆会反复重建处理器，这个继承让每次改动都听不出接缝。
    ///
    /// 长度不同（用户改了延迟）时不继承：把旧历史按新长度重排需要另一套
    /// 逻辑，而那种改动本就伴随延迟量的突变，交给热切换的淡化去盖住即可。
    pub fn inherit_delay_from(&mut self, previous: &Self) {
        if self.delay_samples == 0
            || self.delay_samples != previous.delay_samples
            || self.ring_l.len() != previous.ring_l.len()
        {
            return;
        }
        self.ring_l.copy_from_slice(&previous.ring_l);
        self.ring_r.copy_from_slice(&previous.ring_r);
        self.pos = previous.pos;
    }
}

/// 热切换：在 `xfade_frames` 帧内把交叉馈送从 `previous` 淡到 `current`，
/// 就地写回 `clean`（`clean` 必须是「干净」的、未被交叉馈送处理过的立体声）。
///
/// 两个处理器（都可为 `None`）都会被喂**同一份**干信号：交叉馈送是有状态的
/// 延迟线，若让新处理器去吃旧处理器的输出，串音会被算两次。
///
/// 淡的是**交叉项** `c`（`L_out = L + c`、`R_out = R − c`），不是两路输出。
/// 两个 `c` 由同一份干信号导出，高度相关，用等功率（sin/cos）淡化会在中点
/// 叠加出 +3 dB 的突起，且 `L+R` 在淡化区间不再守恒；对 `c` 做权重 0→1 的
/// 升余弦线性插值，则 `L+R` 逐样本精确守恒，与参考实现一致。
///
/// 只在块边界调用（一次用户操作一次），因此这里的几次分配不在热路径上。
pub fn crossfade_in_place(
    clean: &mut Planar,
    previous: Option<&mut CrossfeedProcessor>,
    current: Option<&mut CrossfeedProcessor>,
    xfade_frames: usize,
) {
    if clean.len() != 2 {
        return;
    }
    let frames = clean[0].len().min(clean[1].len());
    if frames == 0 {
        return;
    }
    let (dry_l, dry_r) = (clean[0][..frames].to_vec(), clean[1][..frames].to_vec());

    // 交叉项 = 处理结果的左声道 − 干信号左声道（因为 L_out = L + c）。
    let term = |proc: Option<&mut CrossfeedProcessor>, l: &[f64], r: &[f64]| -> Vec<f64> {
        let Some(p) = proc else {
            return vec![0.0; l.len()];
        };
        let mut out: Planar = vec![l.to_vec(), r.to_vec()];
        p.process(&mut out);
        out[0].iter().zip(l).map(|(o, d)| o - d).collect()
    };
    let (t_prev, t_new) = (term(previous, &dry_l, &dry_r), term(current, &dry_l, &dry_r));

    let n = xfade_frames.min(frames);
    for i in 0..frames {
        let c = if i < n && n > 0 {
            // 升余弦：两端导数为 0，接缝处听不出拐点；末帧权重精确为 1。
            let w = 0.5 - 0.5 * (PI * (i + 1) as f64 / n as f64).cos();
            t_prev[i] + w * (t_new[i] - t_prev[i])
        } else {
            t_new[i]
        };
        clean[0][i] = dry_l[i] + c;
        clean[1][i] = dry_r[i] - c;
    }
}

/// `delay_ms` → 样本数（越界值先钳到 [`DELAY_MAX_MS`]，避免病态配置无界分配）。
fn ms_to_samples(sample_rate: u32, delay_ms: f64) -> usize {
    let clamped = if delay_ms.is_finite() {
        delay_ms.clamp(0.0, DELAY_MAX_MS)
    } else {
        0.0
    };
    ((clamped / 1000.0) * sample_rate as f64).round() as usize
}

// ---------------------------------------------------------------------------
// 头影低通：目标曲线平直到 `fc`，之后 `s` dB/oct（3 ~ 6）
//
// 实现为最小相位滤波器的级联，每一节都用双线性变换（且对自身频率预畸变，
// 因此极点/零点精确落在设计位置）：
//
// 1. 一个 **膝点** 在 `fc`：`(1 + s/ω) / (1 + s/(Qω) + s²/ω²)`，之后 −6 dB/oct；
//    `Q = 0.5` 时恰好是一阶低通，Q 更高则膝点更陡（`fc` 处衰减更少）；
// 2. 坡度低于 6 dB/oct 时，再级联若干 **平台**（"倾斜"滤波器的做法）：零点在
//    `fc·2^(k+α)`、极点在 `fc·2^(k+1)`，`α = s/6`。每倍频程里 −6 dB/oct 只占
//    `α` 的比例，均值即 −s dB/oct。
//
// 一节的频率超过 `0.45·fs` 就不放置（否则双线性会把接近 Nyquist 的段压得
// 过陡）：此时滤波退化为中性，交叉项原样通过。
// ---------------------------------------------------------------------------

/// 高于该比例的 Nyquist 上限就不再放置某一节。
const SECTION_CEILING_RATIO: f64 = 0.45;
const Q_AT_3_DB: f64 = 0.5;
const Q_AT_6_DB: f64 = 0.61;

#[derive(Debug, Clone, Copy)]
struct ShadowSettings {
    cutoff_hz: f64,
    slope_db_per_octave: f64,
}

/// 二阶节（转置直接 II 型，f64）。
#[derive(Debug, Clone)]
struct Section {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    s1: f64,
    s2: f64,
}

impl Section {
    /// `(n0 + n1·s + n2·s²) / (d0 + d1·s + d2·s²)` 的双线性变换
    /// （`s = 2fs·(1 − z⁻¹)/(1 + z⁻¹)`）。
    fn bilinear(n: [f64; 3], d: [f64; 3], fs: f64) -> Self {
        let k = 2.0 * fs;
        let k2 = k * k;
        let a0 = d[0] + d[1] * k + d[2] * k2;
        Self {
            b0: (n[0] + n[1] * k + n[2] * k2) / a0,
            b1: (2.0 * n[0] - 2.0 * n[2] * k2) / a0,
            b2: (n[0] - n[1] * k + n[2] * k2) / a0,
            a1: (2.0 * d[0] - 2.0 * d[2] * k2) / a0,
            a2: (d[0] - d[1] * k + d[2] * k2) / a0,
            s1: 0.0,
            s2: 0.0,
        }
    }

    #[inline]
    fn process(&mut self, x: f64) -> f64 {
        let y = self.b0 * x + self.s1;
        self.s1 = self.b1 * x - self.a1 * y + self.s2;
        self.s2 = self.b2 * x - self.a2 * y;
        y
    }

    /// 归一化角频率 `w` 处的复响应 `(实, 虚)`。
    fn response(&self, w: f64) -> (f64, f64) {
        let (c1, s1) = (w.cos(), -w.sin());
        let (c2, s2) = ((2.0 * w).cos(), -(2.0 * w).sin());
        let (nr, ni) = (
            self.b0 + self.b1 * c1 + self.b2 * c2,
            self.b1 * s1 + self.b2 * s2,
        );
        let (dr, di) = (
            1.0 + self.a1 * c1 + self.a2 * c2,
            self.a1 * s1 + self.a2 * s2,
        );
        let den = dr * dr + di * di;
        ((nr * dr + ni * di) / den, (ni * dr - nr * di) / den)
    }
}

/// 双线性变换后恰好落在 `f` Hz 的模拟角频率。
fn prewarp(f: f64, fs: f64) -> f64 {
    2.0 * fs * (PI * f / fs).tan()
}

struct ShadowFilter {
    sections: Vec<Section>,
}

impl ShadowFilter {
    fn design(sample_rate: u32, shadow: ShadowSettings) -> Self {
        let fs = f64::from(sample_rate.max(1));
        let ceiling = SECTION_CEILING_RATIO * fs;
        let fc = shadow.cutoff_hz;
        let alpha = shadow.slope_db_per_octave / 6.0;
        let mut sections = Vec::new();
        if fc < ceiling {
            let q = Q_AT_3_DB + (Q_AT_6_DB - Q_AT_3_DB) * (alpha - 0.5) / 0.5;
            let w = prewarp(fc, fs);
            sections.push(Section::bilinear(
                [1.0, 1.0 / w, 0.0],
                [1.0, 1.0 / (q * w), 1.0 / (w * w)],
                fs,
            ));
            if alpha < 1.0 {
                let mut k = 0.0_f64;
                loop {
                    let zero = fc * 2.0_f64.powf(k + alpha);
                    let pole = fc * 2.0_f64.powf(k + 1.0);
                    if pole >= ceiling {
                        break;
                    }
                    let (wz, wp) = (prewarp(zero, fs), prewarp(pole, fs));
                    sections.push(Section::bilinear(
                        [1.0, 1.0 / wz, 0.0],
                        [1.0, 1.0 / wp, 0.0],
                        fs,
                    ));
                    k += 1.0;
                }
            }
        }
        Self { sections }
    }

    #[inline]
    fn process(&mut self, x: f64) -> f64 {
        self.sections.iter_mut().fold(x, |v, s| s.process(v))
    }

    /// 复响应 `(实, 虚)`。
    #[cfg(test)]
    fn response(&self, f: f64, sample_rate: u32) -> (f64, f64) {
        let w = 2.0 * PI * f / f64::from(sample_rate.max(1));
        self.sections.iter().fold((1.0, 0.0), |(r, i), s| {
            let (sr, si) = s.response(w);
            (r * sr - i * si, r * si + i * sr)
        })
    }
}



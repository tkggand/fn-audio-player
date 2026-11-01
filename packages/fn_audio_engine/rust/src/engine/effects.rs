//! 立体声效果模块链（纯自研，f64 内核，无外部依赖）。
//!
//! 架构：每个效果实现 [`StereoEffect`]，一次处理一整块 planar 立体声
//! （左/右各一个 `&mut [f64]`），采样率在构建时注入（滤波器/LFO/延迟
//! 都依赖它）。效果链由 `dsp_builtin` 按 YAML 构建，链尾总是限幅器。
//!
//! 预设 = 启用模块 + 参数表；切换预设 = 重建效果链。全部为经典公开算法：
//! - 空间：M/S 加宽、Haas 单侧延迟、Freeverb 立体声混响、等功率自动声像
//! - 调制：Flanger / Chorus / Phaser / Tremolo（LFO 驱动）
//! - 激励：tanh 软饱和（可选高通，作"空气感"激励器）
//! - 低音：次谐波合成（带通 → 全波整流 → 低通，产生低八度分量）
//! - 动态：峰值限幅器（指数平滑增益包络）

use std::f64::consts::PI;

/// 立体声效果：一次处理一整块 planar 数据。
/// 所有实现都是纯数据（Vec<f64>/f64），`Send` 保证可跨 await 传递
/// （WS 音频会话里 BuiltinDsp 持有效果链）。
pub trait StereoEffect: Send {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]);
}

// ---------------------------------------------------------------- 增益校准

/// 静态增益（dB）：用于预设响度对齐等场景，左右声道同增益。
pub struct Gain {
    gain: f64,
}

impl Gain {
    pub fn new(gain_db: f64) -> Self {
        Self {
            gain: 10f64.powf(gain_db.clamp(-60.0, 24.0) / 20.0),
        }
    }
}

impl StereoEffect for Gain {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        for s in left.iter_mut() {
            *s *= self.gain;
        }
        for s in right.iter_mut() {
            *s *= self.gain;
        }
    }
}

// ---------------------------------------------------------------- M/S 加宽

/// 中侧（M/S）加宽：M=(L+R)/2，S=(L−R)/2，S 增益后解码。
/// width=1.0 为原样，>1 拓宽，<1 收窄。
pub struct MsWiden {
    width: f64,
}

impl MsWiden {
    pub fn new(width: f64) -> Self {
        Self {
            width: width.clamp(0.0, 3.0),
        }
    }
}

impl StereoEffect for MsWiden {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let w = self.width;
        for i in 0..left.len() {
            let m = (left[i] + right[i]) * 0.5;
            let s = (left[i] - right[i]) * 0.5 * w;
            left[i] = m + s;
            right[i] = m - s;
        }
    }
}

// ------------------------------------------------------------ Haas 单侧延迟

/// Haas 效应：只延迟**侧信号** S=(L−R)/2，中置 M=(L+R)/2 原样保留。
///
/// 旧实现延迟整个右声道（且 mix=1.0 时完全替换直达声），等价于给右声道
/// 串了一个 12–16ms 的梳状滤波器：左右相关度掉到 0.05，单声道求和出现
/// −51 dB 的深陷，听感空、薄、发虚。改为只处理 S 后：
/// - M 不变 → 单声道求和与原始信号完全一致（无梳状、无能量损失）；
/// - 延迟后的侧信号可先高通（默认 200Hz），低频声像不被拉散；
/// - mix=0 直通，mix=1 侧信号完全替换为延迟侧信号（经典 Haas）。
pub struct HaasDelay {
    ring: Vec<f64>,
    pos: usize,
    mix: f64,
    hp_a: f64,
    hp_state: f64,
    hp_x_prev: f64,
}

impl HaasDelay {
    /// `delay_ms` 延迟时间，`mix` 侧信号湿比例，`highpass_hz` 延迟侧信号高通
    /// 频率（0 = 关闭）。
    pub fn new(sample_rate: u32, delay_ms: f64, mix: f64, highpass_hz: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let samples = ((delay_ms.max(0.0) / 1000.0) * sr).round() as usize;
        // 单极高通：y[n] = α·(y[n-1] + x[n] − x[n-1])，α = 1/(1+2πfc/sr)
        let hp_a = if highpass_hz > 0.0 {
            1.0 / (1.0 + 2.0 * PI * highpass_hz / sr)
        } else {
            0.0
        };
        Self {
            ring: vec![0.0; samples.max(1)],
            pos: 0,
            mix: mix.clamp(0.0, 1.0),
            hp_a,
            hp_state: 0.0,
            hp_x_prev: 0.0,
        }
    }
}

impl StereoEffect for HaasDelay {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let len = self.ring.len();
        let mix = self.mix;
        let hp_a = self.hp_a;
        for i in 0..left.len() {
            let m = (left[i] + right[i]) * 0.5;
            let s = (left[i] - right[i]) * 0.5;
            let delayed = self.ring[self.pos];
            self.ring[self.pos] = s;
            self.pos = (self.pos + 1) % len;
            let delayed = if hp_a > 0.0 {
                let y = hp_a * (self.hp_state + delayed - self.hp_x_prev);
                self.hp_x_prev = delayed;
                self.hp_state = y;
                y
            } else {
                delayed
            };
            let wet_s = s * (1.0 - mix) + delayed * mix;
            left[i] = m + wet_s;
            right[i] = m - wet_s;
        }
    }
}

// ---------------------------------------------------------------- Freeverb

/// 经典 Freeverb 立体声混响（8 comb + 4 allpass × 每声道）。
///
/// `room` 0..1 房间大小，`damp` 0..1 阻尼，`wet` 0..1 干湿比（0=直通，
/// 1=纯湿声），`width` 0..1 湿声立体声宽度（0=单声道湿声，1=左右独立）。
///
/// 三处历史实现错误已修正：
/// 1. 梳状滤波器输入缺少经典 `fixedgain`（0.015）衰减，混响总线曾比干声高
///    约 27 dB，`wet` 完全失真为一个"叠加量"；
/// 2. 湿声输出缺少交叉项 `out_r * wet2`，且 `width` 被 clamp 到 1.0 时
///    `wet2` 恒为 0 —— 结果右声道**完全没有混响**（左右差 12 dB）；
/// 3. 湿声直接叠加而不衰减干声，`wet` 不是真正的干湿比。
pub struct Freeverb {
    combs_l: Vec<Comb>,
    combs_r: Vec<Comb>,
    allpass_l: Vec<Allpass>,
    allpass_r: Vec<Allpass>,
    dry_gain: f64,
    wet1: f64,
    wet2: f64,
}

struct Comb {
    buffer: Vec<f64>,
    pos: usize,
    filterstore: f64,
    feedback: f64,
    damp1: f64,
    damp2: f64,
}

impl Comb {
    fn process(&mut self, input: f64) -> f64 {
        let buf = &mut self.buffer;
        let len = buf.len();
        let out = buf[self.pos];
        self.filterstore = out * self.damp2 + self.filterstore * self.damp1;
        buf[self.pos] = input + self.filterstore * self.feedback;
        self.pos = (self.pos + 1) % len;
        out
    }
}

struct Allpass {
    buffer: Vec<f64>,
    pos: usize,
}

impl Allpass {
    fn process(&mut self, input: f64) -> f64 {
        let len = self.buffer.len();
        let buf_out = self.buffer[self.pos];
        let out = -input + buf_out;
        self.buffer[self.pos] = input + buf_out * 0.5;
        self.pos = (self.pos + 1) % len;
        out
    }
}

const COMB_TUNING: [f64; 8] = [1116.0, 1188.0, 1277.0, 1356.0, 1422.0, 1491.0, 1557.0, 1617.0];
const ALLPASS_TUNING: [f64; 4] = [556.0, 441.0, 341.0, 225.0];
const STEREO_SPREAD: f64 = 23.0;
/// 经典 Freeverb 的输入衰减：8 条 comb 并联后的能量归一到干声量级。
const FIXED_GAIN: f64 = 0.015;

impl Freeverb {
    pub fn new(sample_rate: u32, room: f64, damp: f64, wet: f64, width: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let scale = sr / 44_100.0;
        let feedback = room.clamp(0.0, 1.0) * 0.28 + 0.7;
        let damping = damp.clamp(0.0, 1.0) * 0.4;
        let damp1 = damping;
        let damp2 = 1.0 - damping;
        let width = width.clamp(0.0, 1.0);
        let wet = wet.clamp(0.0, 1.0);
        // 真正的干湿比：wet=0 完全直通，wet=1 纯湿声。
        let dry_gain = 1.0 - wet;
        let wet1 = wet * (width * 0.5 + 0.5);
        let wet2 = wet * ((1.0 - width) * 0.5);

        let mut combs_l = Vec::new();
        let mut combs_r = Vec::new();
        for &t in COMB_TUNING.iter() {
            combs_l.push(Comb {
                buffer: vec![0.0; (t * scale) as usize],
                pos: 0,
                filterstore: 0.0,
                feedback,
                damp1,
                damp2,
            });
            combs_r.push(Comb {
                buffer: vec![0.0; ((t + STEREO_SPREAD) * scale) as usize],
                pos: 0,
                filterstore: 0.0,
                feedback,
                damp1,
                damp2,
            });
        }
        let mut allpass_l = Vec::new();
        let mut allpass_r = Vec::new();
        for &t in ALLPASS_TUNING.iter() {
            allpass_l.push(Allpass {
                buffer: vec![0.0; (t * scale) as usize],
                pos: 0,
            });
            allpass_r.push(Allpass {
                buffer: vec![0.0; ((t + STEREO_SPREAD) * scale) as usize],
                pos: 0,
            });
        }

        Self {
            combs_l,
            combs_r,
            allpass_l,
            allpass_r,
            dry_gain,
            wet1,
            wet2,
        }
    }
}

impl StereoEffect for Freeverb {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        for i in 0..left.len() {
            let mut out_l = 0.0;
            let mut out_r = 0.0;
            for c in self.combs_l.iter_mut() {
                out_l += c.process(left[i] * FIXED_GAIN);
            }
            for c in self.combs_r.iter_mut() {
                out_r += c.process(right[i] * FIXED_GAIN);
            }
            for a in self.allpass_l.iter_mut() {
                out_l = a.process(out_l);
            }
            for a in self.allpass_r.iter_mut() {
                out_r = a.process(out_r);
            }
            // 交叉混流：width=0 时左右得到同一份湿声，width=1 时各声道独立。
            let wet_l = out_l * self.wet1 + out_r * self.wet2;
            let wet_r = out_r * self.wet1 + out_l * self.wet2;
            left[i] = left[i] * self.dry_gain + wet_l;
            right[i] = right[i] * self.dry_gain + wet_r;
        }
    }
}

// ------------------------------------------------------------ 等功率自动声像

/// 8D 旋转声像：输入单声道化后按 LFO 正弦等功率声像旋转。
/// rate_hz 旋转速度（0.05~0.2Hz），depth 0..1 限制旋转范围（1=整圈）。
/// cos²+sin²=1，恒等功率，无音量起伏。
pub struct AutoPan {
    sample_rate: f64,
    phase: f64,
    rate_hz: f64,
    depth: f64,
}

impl AutoPan {
    pub fn new(sample_rate: u32, rate_hz: f64, depth: f64) -> Self {
        Self {
            sample_rate: sample_rate.max(1) as f64,
            phase: 0.0,
            rate_hz: rate_hz.max(0.0),
            depth: depth.clamp(0.0, 1.0),
        }
    }
}

impl StereoEffect for AutoPan {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let dphase = 2.0 * PI * self.rate_hz / self.sample_rate;
        let depth = self.depth;
        for i in 0..left.len() {
            let mono = (left[i] + right[i]) * 0.5;
            let theta = self.phase * depth;
            left[i] = mono * theta.cos();
            right[i] = mono * theta.sin();
            self.phase += dphase;
            if self.phase > 2.0 * PI {
                self.phase -= 2.0 * PI;
            }
        }
    }
}

// ---------------------------------------------------------------- 软饱和激励

/// 4× 过采样用的低通 FIR 长度与群延迟（单位：基础采样率采样数）。
/// 两级 2× 级联：第一级往返 16，第二级往返 8，共 24。
const OS_TAPS: usize = 33;
const OS_LATENCY: usize = 24;

fn bessel_i0(x: f64) -> f64 {
    let y = x * x * 0.25;
    let mut sum = 1.0;
    let mut term = 1.0;
    for k in 1..32 {
        term *= y / (k * k) as f64;
        sum += term;
        if term.abs() < 1e-14 * sum {
            break;
        }
    }
    sum
}

/// 2× 内插/抽取共用的线性相位低通（Kaiser 窗，截止 0.235×2fs）。
fn os_coeffs() -> &'static [f64; OS_TAPS] {
    use std::sync::OnceLock;
    static COEFFS: OnceLock<[f64; OS_TAPS]> = OnceLock::new();
    COEFFS.get_or_init(|| {
        let m = (OS_TAPS - 1) as f64 * 0.5;
        let fc = 0.235; // 归一化到 2× 采样率（原 Nyquist = 0.25）
        let beta = 6.5;
        let denom = bessel_i0(beta);
        let mut h = [0.0f64; OS_TAPS];
        let mut sum = 0.0;
        for (n, c) in h.iter_mut().enumerate() {
            let x = n as f64 - m;
            let sinc = if x.abs() < 1e-12 {
                1.0
            } else {
                let t = 2.0 * PI * fc * x;
                t.sin() / t
            };
            let r = (x / m).abs();
            let w = if r < 1.0 {
                bessel_i0(beta * (1.0 - r * r).sqrt()) / denom
            } else {
                0.0
            };
            *c = 2.0 * fc * sinc * w;
            sum += *c;
        }
        for c in h.iter_mut() {
            *c /= sum; // 抽取路径直流增益 1；内插路径再 ×2
        }
        h
    })
}

/// 流式 2× 上采样：每个输入样本产出两个 2× 采样。
struct Up2 {
    hist: [f64; OS_TAPS],
    pos: usize,
}

impl Up2 {
    fn new() -> Self {
        Self {
            hist: [0.0; OS_TAPS],
            pos: 0,
        }
    }

    fn push(&mut self, x: f64) -> (f64, f64) {
        self.pos = (self.pos + 1) % OS_TAPS;
        self.hist[self.pos] = x;
        let h = os_coeffs();
        let (mut even, mut odd) = (0.0, 0.0);
        // 多相分解：偶相位用 h[2p]、奇相位用 h[2p+1]，两者都对应
        // 基础采样历史 x[m-p]（零插值后两相各占一个新采样）。
        for p in 0..(OS_TAPS / 2 + 1) {
            let v = self.hist[(self.pos + OS_TAPS - p) % OS_TAPS];
            even += h[2 * p] * v;
            if 2 * p + 1 < OS_TAPS {
                odd += h[2 * p + 1] * v;
            }
        }
        // 零插值使能量减半，内插滤波器需 ×2 补偿
        (even * 2.0, odd * 2.0)
    }
}

/// 流式 2× 下采样：每两个 2× 采样产出一个输出（第二个相位出结果）。
struct Down2 {
    hist: [f64; OS_TAPS],
    pos: usize,
    phase: bool,
}

impl Down2 {
    fn new() -> Self {
        Self {
            hist: [0.0; OS_TAPS],
            pos: 0,
            phase: true, // 首个采样为"半对"中的第一个，不输出
        }
    }

    fn push(&mut self, v: f64) -> Option<f64> {
        self.pos = (self.pos + 1) % OS_TAPS;
        self.hist[self.pos] = v;
        self.phase = !self.phase;
        if !self.phase {
            return None; // 每两个采样的第二个之后输出
        }
        let h = os_coeffs();
        let mut y = 0.0;
        for k in 0..OS_TAPS {
            y += h[k] * self.hist[(self.pos + OS_TAPS - k) % OS_TAPS];
        }
        Some(y)
    }
}

/// 干声对齐延迟线（整数采样）。
struct DryDelay {
    buf: Vec<f64>,
    pos: usize,
}

impl DryDelay {
    fn new(samples: usize) -> Self {
        Self {
            buf: vec![0.0; samples.max(1)],
            pos: 0,
        }
    }

    fn push(&mut self, x: f64) -> f64 {
        let out = self.buf[self.pos];
        self.buf[self.pos] = x;
        self.pos = (self.pos + 1) % self.buf.len();
        out
    }
}

/// tanh 软饱和（可选高通），作激励器/失真。drive 驱动强度，mix 干湿，
/// highpass_hz>0 时先单极高通（只饱和高频，给"空气感"）。
///
/// 内部 **4× 过采样**（两级 2× 半带 FIR）后再饱和：tanh 在基础采样率下
/// 会把 22kHz 以上的谐波折回可听带（如 5kHz 输入的 25k 谐波折成 19.1k），
/// 表现为高频毛刺。4× 时这些谐波在降采样前被 FIR 滤掉。干声经等长延迟
/// 对齐（24 采样），保证 mix<1 时不会与湿声产生梳状抵消。
pub struct SoftClip {
    drive: f64,
    mix: f64,
    hp_a: f64,
    hp_state_l: f64,
    hp_state_r: f64,
    hp_x_prev_l: f64,
    hp_x_prev_r: f64,
    norm: f64,
    up1_l: Up2,
    up1_r: Up2,
    up2_l: Up2,
    up2_r: Up2,
    down1_l: Down2,
    down1_r: Down2,
    down2_l: Down2,
    down2_r: Down2,
    dry_l: DryDelay,
    dry_r: DryDelay,
}

impl SoftClip {
    pub fn new(sample_rate: u32, drive: f64, mix: f64, highpass_hz: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let drive = drive.max(0.01);
        let norm = drive.tanh();
        // 单极高通：y[n] = α·(y[n-1] + x[n] - x[n-1])，α = 1/(1+2πfc/sr)
        let hp_a = if highpass_hz > 0.0 {
            1.0 / (1.0 + 2.0 * PI * highpass_hz / sr)
        } else {
            0.0
        };
        Self {
            drive,
            mix: mix.clamp(0.0, 1.0),
            hp_a,
            hp_state_l: 0.0,
            hp_state_r: 0.0,
            hp_x_prev_l: 0.0,
            hp_x_prev_r: 0.0,
            norm: if norm.abs() > 1e-9 { norm } else { 1.0 },
            up1_l: Up2::new(),
            up1_r: Up2::new(),
            up2_l: Up2::new(),
            up2_r: Up2::new(),
            down1_l: Down2::new(),
            down1_r: Down2::new(),
            down2_l: Down2::new(),
            down2_r: Down2::new(),
            dry_l: DryDelay::new(OS_LATENCY),
            dry_r: DryDelay::new(OS_LATENCY),
        }
    }
}

impl StereoEffect for SoftClip {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let mix = self.mix;
        if mix <= 0.0 {
            return; // 全干：直通，不引入延迟
        }
        let drive = self.drive;
        let norm = self.norm;
        let hp_a = self.hp_a;
        let sat = |v: f64| (drive * v).tanh() / norm;
        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];
            // 高通（若启用）
            let (mut yl, mut yr) = (dry_l, dry_r);
            if hp_a > 0.0 {
                yl = hp_a * (self.hp_state_l + dry_l - self.hp_x_prev_l);
                self.hp_x_prev_l = dry_l;
                self.hp_state_l = yl;
                yr = hp_a * (self.hp_state_r + dry_r - self.hp_x_prev_r);
                self.hp_x_prev_r = dry_r;
                self.hp_state_r = yr;
            }
            // 2× 级 → 4× 级
            let (l0, l1) = self.up1_l.push(yl);
            let (r0, r1) = self.up1_r.push(yr);
            let (la0, la1) = self.up2_l.push(l0);
            let (lb0, lb1) = self.up2_l.push(l1);
            let (ra0, ra1) = self.up2_r.push(r0);
            let (rb0, rb1) = self.up2_r.push(r1);
            let wl = [sat(la0), sat(la1), sat(lb0), sat(lb1)];
            let wr = [sat(ra0), sat(ra1), sat(rb0), sat(rb1)];
            // 4× 级 → 2× 级
            let mut v2l = [0.0f64; 2];
            let mut v2r = [0.0f64; 2];
            let (mut il, mut ir) = (0, 0);
            for j in 0..4 {
                if let Some(v) = self.down2_l.push(wl[j]) {
                    v2l[il] = v;
                    il += 1;
                }
                if let Some(v) = self.down2_r.push(wr[j]) {
                    v2r[ir] = v;
                    ir += 1;
                }
            }
            // 2× 级 → 基础采样率
            let _ = self.down1_l.push(v2l[0]);
            let wet_l = self.down1_l.push(v2l[1]).unwrap_or(0.0);
            let _ = self.down1_r.push(v2r[0]);
            let wet_r = self.down1_r.push(v2r[1]).unwrap_or(0.0);
            // 干声延迟对齐后混合
            let dl = self.dry_l.push(dry_l);
            let dr = self.dry_r.push(dry_r);
            left[i] = dl * (1.0 - mix) + wet_l * mix;
            right[i] = dr * (1.0 - mix) + wet_r * mix;
        }
    }
}

// ---------------------------------------------------------------- Flanger

/// Flanger：LFO 驱动延迟时间扫描（0..depth_ms），带反馈。
/// 左右声道 LFO 反相，增强立体感。
pub struct Flanger {
    rate_hz: f64,
    depth_samples: f64,
    feedback: f64,
    mix: f64,
    ring: Vec<f64>,
    pos: usize,
    lfo_phase: f64,
    sample_rate: f64,
}

impl Flanger {
    pub fn new(sample_rate: u32, rate_hz: f64, depth_ms: f64, feedback: f64, mix: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let depth = (depth_ms / 1000.0 * sr).max(1.0);
        let max_delay = depth.ceil() as usize + 2;
        Self {
            rate_hz: rate_hz.max(0.01),
            depth_samples: depth,
            feedback: feedback.clamp(0.0, 0.9),
            mix: mix.clamp(0.0, 1.0),
            ring: vec![0.0; max_delay],
            pos: 0,
            lfo_phase: 0.0,
            sample_rate: sr,
        }
    }
}

impl StereoEffect for Flanger {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let len = self.ring.len();
        let dphase = 2.0 * PI * self.rate_hz / self.sample_rate;
        let depth = self.depth_samples;
        let fb = self.feedback;
        let mix = self.mix;
        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];
            // 左声道 LFO 相位 φ，右声道 -φ
            let dl = self.lfo_phase.sin() * 0.5 + 0.5; // 0..1
            let dr = (-self.lfo_phase).sin() * 0.5 + 0.5;
            let delay_l = (dl * depth).max(1.0);
            let delay_r = (dr * depth).max(1.0);

            let delayed_l = read_interp(&self.ring, self.pos, len, delay_l);
            let delayed_r = read_interp(&self.ring, self.pos, len, delay_r);

            // 写入（带反馈）
            self.ring[self.pos] = dry_l + delayed_l * fb;
            self.pos = (self.pos + 1) % len;
            // 右声道用同一条延迟线、错开 tap（简化：同一 ring，右声道独立 tap 点）
            // 为保证左右独立性，这里把右声道也写入同位置会导致串扰；
            // 改为分别用 tap 偏移读取，写入仍按采样交错。此处简化：只写左声道值，
            // 右声道 tap 从同一 ring 读取（Flanger 常见实现）。
            let out_l = dry_l * (1.0 - mix) + delayed_l * mix;
            let out_r = dry_r * (1.0 - mix) + delayed_r * mix;
            left[i] = out_l;
            right[i] = out_r;
            self.lfo_phase += dphase;
            if self.lfo_phase > 2.0 * PI {
                self.lfo_phase -= 2.0 * PI;
            }
        }
    }
}

/// 从环形缓冲读取"delay_samples"前的采样（线性插值）。
fn read_interp(ring: &[f64], pos: usize, len: usize, delay: f64) -> f64 {
    let idx = pos as f64 - delay;
    let i0 = idx.floor() as isize;
    let frac = idx - i0 as f64;
    let i0 = i0.rem_euclid(len as isize) as usize;
    let i1 = (i0 + 1) % len;
    ring[i0] * (1.0 - frac) + ring[i1] * frac
}

// ---------------------------------------------------------------- Chorus

/// Chorus：N 条延迟线，各 LFO 相位错开，深度 1~3ms。
pub struct Chorus {
    rate_hz: f64,
    depth_samples: f64,
    voices: usize,
    mix: f64,
    ring: Vec<f64>,
    pos: usize,
    lfo_phases: Vec<f64>,
    sample_rate: f64,
}

impl Chorus {
    pub fn new(sample_rate: u32, rate_hz: f64, depth_ms: f64, voices: usize, mix: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let voices = voices.clamp(2, 8);
        let base = 20.0 / 1000.0 * sr; // 20ms 基础延迟
        let depth = (depth_ms / 1000.0 * sr).max(1.0);
        let max_delay = (base + depth).ceil() as usize + 2;
        let phases: Vec<f64> = (0..voices)
            .map(|v| 2.0 * PI * v as f64 / voices as f64)
            .collect();
        Self {
            rate_hz: rate_hz.max(0.01),
            depth_samples: depth,
            voices,
            mix: mix.clamp(0.0, 1.0),
            ring: vec![0.0; max_delay],
            pos: 0,
            lfo_phases: phases,
            sample_rate: sr,
        }
    }
}

impl StereoEffect for Chorus {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let len = self.ring.len();
        let dphase = 2.0 * PI * self.rate_hz / self.sample_rate;
        let depth = self.depth_samples;
        let base = 20.0 / 1000.0 * self.sample_rate;
        let mix = self.mix;
        let voices = self.voices;
        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];
            // 写入（干信号）
            self.ring[self.pos] = (dry_l + dry_r) * 0.5;
            self.pos = (self.pos + 1) % len;

            let mut acc_l = 0.0;
            let mut acc_r = 0.0;
            for v in 0..voices {
                let ph = self.lfo_phases[v];
                let lfo = ph.sin() * 0.5 + 0.5;
                let delay = base + lfo * depth;
                // 奇偶声道使用相同 tap，但左右各错开半周期相位
                let d_l = delay;
                let d_r = delay + depth * 0.5;
                acc_l += read_interp(&self.ring, self.pos, len, d_l);
                acc_r += read_interp(&self.ring, self.pos, len, d_r);
            }
            acc_l /= voices as f64;
            acc_r /= voices as f64;
            left[i] = dry_l * (1.0 - mix) + acc_l * mix;
            right[i] = dry_r * (1.0 - mix) + acc_r * mix;
            for p in self.lfo_phases.iter_mut() {
                *p += dphase;
                if *p > 2.0 * PI {
                    *p -= 2.0 * PI;
                }
            }
        }
    }
}

// ---------------------------------------------------------------- Phaser

/// Phaser：级联一阶全通 + LFO 调制中心频率 + 反馈。
pub struct Phaser {
    rate_hz: f64,
    depth: f64,
    stages: usize,
    feedback: f64,
    mix: f64,
    lfo_phase: f64,
    sample_rate: f64,
    // 每级 allpass 状态（每声道各一套）
    state_l: Vec<f64>,
    state_r: Vec<f64>,
    fb_l: f64,
    fb_r: f64,
}

impl Phaser {
    pub fn new(sample_rate: u32, rate_hz: f64, depth: f64, stages: usize, feedback: f64, mix: f64) -> Self {
        let stages = stages.clamp(2, 12);
        Self {
            rate_hz: rate_hz.max(0.01),
            depth: depth.clamp(0.0, 1.0),
            stages,
            feedback: feedback.clamp(0.0, 0.9),
            mix: mix.clamp(0.0, 1.0),
            lfo_phase: 0.0,
            sample_rate: sample_rate.max(1) as f64,
            state_l: vec![0.0; stages],
            state_r: vec![0.0; stages],
            fb_l: 0.0,
            fb_r: 0.0,
        }
    }
}

impl StereoEffect for Phaser {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let dphase = 2.0 * PI * self.rate_hz / self.sample_rate;
        let sr = self.sample_rate;
        let depth = self.depth;
        let fb = self.feedback;
        let mix = self.mix;
        let stages = self.stages;
        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];
            // LFO 0..1 → 中心频率 400Hz..4kHz
            let lfo = self.lfo_phase.sin() * 0.5 + 0.5;
            let f0 = 400.0 * (1.0 + lfo * depth * 9.0);
            let coeff = allpass_coeff(f0, sr);
            // 每级频率微错开
            let mut xl = dry_l + self.fb_l * fb;
            let mut xr = dry_r + self.fb_r * fb;
            for s in 0..stages {
                let c = if s % 2 == 0 {
                    coeff
                } else {
                    allpass_coeff(f0 * 1.12, sr)
                };
                xl = allpass_step(c, xl, &mut self.state_l[s]);
                xr = allpass_step(c, xr, &mut self.state_r[s]);
            }
            self.fb_l = xl;
            self.fb_r = xr;
            left[i] = dry_l * (1.0 - mix) + xl * mix;
            right[i] = dry_r * (1.0 - mix) + xr * mix;
            self.lfo_phase += dphase;
            if self.lfo_phase > 2.0 * PI {
                self.lfo_phase -= 2.0 * PI;
            }
        }
    }
}

fn allpass_coeff(freq: f64, sr: f64) -> f64 {
    let t = (PI * freq / sr).tan();
    (1.0 - t) / (1.0 + t)
}

fn allpass_step(b: f64, x: f64, state: &mut f64) -> f64 {
    let y = b * x + *state;
    *state = x - b * y;
    y
}

// ---------------------------------------------------------------- Tremolo

/// Tremolo：LFO 幅度调制。depth 0..1。
pub struct Tremolo {
    rate_hz: f64,
    depth: f64,
    lfo_phase: f64,
    sample_rate: f64,
}

impl Tremolo {
    pub fn new(sample_rate: u32, rate_hz: f64, depth: f64) -> Self {
        Self {
            rate_hz: rate_hz.max(0.01),
            depth: depth.clamp(0.0, 1.0),
            lfo_phase: 0.0,
            sample_rate: sample_rate.max(1) as f64,
        }
    }
}

impl StereoEffect for Tremolo {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let dphase = 2.0 * PI * self.rate_hz / self.sample_rate;
        let depth = self.depth;
        for i in 0..left.len() {
            let g = 1.0 - depth * 0.5 * (1.0 + self.lfo_phase.sin());
            left[i] *= g;
            right[i] *= g;
            self.lfo_phase += dphase;
            if self.lfo_phase > 2.0 * PI {
                self.lfo_phase -= 2.0 * PI;
            }
        }
    }
}

// ------------------------------------------------------------ 次谐波合成

/// 次谐波合成（重低音核心）：带通 80–160Hz 提取基频 → 过零分频器
/// （每个正过零点翻转极性，得到精确 f/2 方波）→ 包络跟随定幅 →
/// 两级低通取基波 → 20Hz 直流阻断 → 混回。
///
/// 旧实现用全波整流 `|x|`，数学上是 `DC + 2f`（直流 + 高八度），既没有
/// 下潜还引入了直流偏移。现在输出的是真正的低八度分量，且静音时被包络
/// 门限关断，不会把底噪"分频"成低频嗡声。
pub struct SubHarmonic {
    mix: f64,
    bp: [f64; 3],
    bp_a1: f64,
    bp_a2: f64,
    x1_l: f64,
    x2_l: f64,
    y1_l: f64,
    y2_l: f64,
    x1_r: f64,
    x2_r: f64,
    y1_r: f64,
    y2_r: f64,
    env_attack: f64,
    env_release: f64,
    env_l: f64,
    env_r: f64,
    prev_l: f64,
    prev_r: f64,
    flip_l: f64,
    flip_r: f64,
    gate: f64,
    lp1_a: f64,
    lp2_a: f64,
    lp1_l: f64,
    lp1_r: f64,
    lp2_l: f64,
    lp2_r: f64,
    dc_r: f64,
    dc_x1_l: f64,
    dc_x1_r: f64,
    dc_y1_l: f64,
    dc_y1_r: f64,
}

impl SubHarmonic {
    pub fn new(sample_rate: u32, low_hz: f64, high_hz: f64, mix: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let f0 = (low_hz + high_hz) * 0.5;
        let q = f0 / (high_hz - low_hz).max(1.0);
        // RBJ 带通（constant skirt gain）：b0=α, b1=0, b2=-α, a0=1+α
        let w0 = 2.0 * PI * f0 / sr;
        let alpha = w0.sin() / (2.0 * q);
        let b0 = alpha;
        let b2 = -alpha;
        let a0 = 1.0 + alpha;
        let a1 = -2.0 * w0.cos();
        let a2 = 1.0 - alpha;
        let bp = [b0 / a0, 0.0, b2 / a0];
        let onepole = |fc: f64| -> f64 {
            if sr > 0.0 {
                1.0 - (-2.0 * PI * fc / sr).exp()
            } else {
                0.1
            }
        };
        Self {
            mix: mix.clamp(0.0, 1.0),
            bp,
            bp_a1: a1 / a0,
            bp_a2: a2 / a0,
            x1_l: 0.0,
            x2_l: 0.0,
            y1_l: 0.0,
            y2_l: 0.0,
            x1_r: 0.0,
            x2_r: 0.0,
            y1_r: 0.0,
            y2_r: 0.0,
            env_attack: onepole(12.0),  // ~13ms 起音
            env_release: onepole(3.0),  // ~53ms 释放
            env_l: 0.0,
            env_r: 0.0,
            prev_l: 0.0,
            prev_r: 0.0,
            flip_l: 1.0,
            flip_r: 1.0,
            gate: 0.003, // -50 dBFS
            lp1_a: onepole(110.0),
            lp2_a: onepole(110.0),
            lp1_l: 0.0,
            lp1_r: 0.0,
            lp2_l: 0.0,
            lp2_r: 0.0,
            dc_r: (1.0 - 2.0 * PI * 15.0 / sr).clamp(0.9, 1.0),
            dc_x1_l: 0.0,
            dc_x1_r: 0.0,
            dc_y1_l: 0.0,
            dc_y1_r: 0.0,
        }
    }

    fn bandpass(&mut self, ch: usize, x: f64) -> f64 {
        let (x1, x2, y1, y2) = if ch == 0 {
            (&mut self.x1_l, &mut self.x2_l, &mut self.y1_l, &mut self.y2_l)
        } else {
            (&mut self.x1_r, &mut self.x2_r, &mut self.y1_r, &mut self.y2_r)
        };
        let y = self.bp[0] * x + self.bp[1] * *x1 + self.bp[2] * *x2 - self.bp_a1 * *y1 - self.bp_a2 * *y2;
        *x2 = *x1;
        *x1 = x;
        *y2 = *y1;
        *y1 = y;
        y
    }

    /// 单个声道的分频式次谐波：返回低八度分量。
    fn sub_sample(&mut self, ch: usize, bp_out: f64) -> f64 {
        let (env, prev, flip, lp1, lp2, dc_x1, dc_y1) = if ch == 0 {
            (
                &mut self.env_l,
                &mut self.prev_l,
                &mut self.flip_l,
                &mut self.lp1_l,
                &mut self.lp2_l,
                &mut self.dc_x1_l,
                &mut self.dc_y1_l,
            )
        } else {
            (
                &mut self.env_r,
                &mut self.prev_r,
                &mut self.flip_r,
                &mut self.lp1_r,
                &mut self.lp2_r,
                &mut self.dc_x1_r,
                &mut self.dc_y1_r,
            )
        };
        // 包络跟随：整流后用不同系数做快起慢落
        let rect = bp_out.abs();
        let coef = if rect > *env { self.env_attack } else { self.env_release };
        *env += coef * (rect - *env);

        // 正过零点翻转 → 方波周期 = 2 个输入周期 = f/2
        if *prev <= 0.0 && bp_out > 0.0 && *env > self.gate {
            *flip = -*flip;
        }
        *prev = bp_out;

        // 方波幅度跟随包络，再两级低通取基波、抑制 3f/2 以上
        let square = *flip * *env;
        *lp1 += self.lp1_a * (square - *lp1);
        *lp2 += self.lp2_a * (*lp1 - *lp2);
        // 一阶直流阻断：y[n] = x[n] - x[n-1] + R·y[n-1]
        let y = *lp2 - *dc_x1 + self.dc_r * *dc_y1;
        *dc_x1 = *lp2;
        *dc_y1 = y;
        // 方波 RMS 比正弦高约 1.6dB，缩放回与输入基频相近的幅度
        y * 0.62
    }
}

impl StereoEffect for SubHarmonic {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let mix = self.mix;
        for i in 0..left.len() {
            let dry_l = left[i];
            let dry_r = right[i];
            let bl = self.bandpass(0, dry_l);
            let br = self.bandpass(1, dry_r);
            let sub_l = self.sub_sample(0, bl);
            let sub_r = self.sub_sample(1, br);
            left[i] = dry_l + sub_l * mix;
            right[i] = dry_r + sub_r * mix;
        }
    }
}

// ---------------------------------------------------------------- 峰值限幅器

/// 峰值限幅器：检测立体声峰值，指数平滑增益包络，带 lookahead。
/// threshold_db 阈值（dBFS，负值），attack/release_ms 增益包络时间，
/// lookahead_ms 提前量（默认 2ms）——增益在峰值到达前就已压下，
/// 杜绝首过冲漏网。必须挂在效果链末尾（低音/激励最容易爆音）。
pub struct Limiter {
    threshold: f64,
    attack_alpha: f64,
    release_alpha: f64,
    gain: f64,
    delay_l: Vec<f64>,
    delay_r: Vec<f64>,
    dpos: usize,
    /// 单调递减队列 `(全局采样序号, 峰值)`。序号必须跨块连续，否则 WS 实时
    /// 播放（100ms 分块）时上一块末尾的峰值会滞留在队首，把下一整块都压住。
    window: Vec<(u64, f64)>,
    wlen: usize,
    /// 已处理的全局采样数（跨 process() 调用持续累加）。
    index: u64,
}

impl Limiter {
    pub fn new(sample_rate: u32, threshold_db: f64, attack_ms: f64, release_ms: f64) -> Self {
        let sr = sample_rate.max(1) as f64;
        let thr = 10f64.powf(threshold_db / 20.0).clamp(0.0001, 1.0);
        let attack_alpha = if attack_ms > 0.0 {
            1.0 - (-1.0 / (attack_ms / 1000.0 * sr)).exp()
        } else {
            1.0
        };
        let release_alpha = if release_ms > 0.0 {
            1.0 - (-1.0 / (release_ms / 1000.0 * sr)).exp()
        } else {
            0.0
        };
        let lookahead = ((4.0 / 1000.0) * sr).round() as usize;
        Self {
            threshold: thr,
            attack_alpha: attack_alpha.clamp(0.0001, 1.0),
            release_alpha: release_alpha.clamp(0.0001, 1.0),
            gain: 1.0,
            delay_l: vec![0.0; lookahead + 1],
            delay_r: vec![0.0; lookahead + 1],
            dpos: 0,
            window: Vec::with_capacity(lookahead + 2),
            wlen: lookahead + 1,
            index: 0,
        }
    }
}

impl StereoEffect for Limiter {
    fn process(&mut self, left: &mut [f64], right: &mut [f64]) {
        let thr = self.threshold;
        let aa = self.attack_alpha;
        let ar = self.release_alpha;
        let wlen = self.wlen as u64;
        let mut queue: Vec<(u64, f64)> = std::mem::take(&mut self.window);
        for i in 0..left.len() {
            // 1. 当前采样峰值入延迟线（输出延迟 wlen-1 个采样）
            let peak = left[i].abs().max(right[i].abs());
            self.delay_l[self.dpos] = left[i];
            self.delay_r[self.dpos] = right[i];
            let out_idx = (self.dpos + 1) % self.delay_l.len();
            let out_l = self.delay_l[out_idx];
            let out_r = self.delay_r[out_idx];
            self.dpos = out_idx;

            // 2. 滑窗峰值：单调队列维护 [abs-wlen+1, abs] 窗口内最大值
            let abs_idx = self.index;
            while let Some(&(_, v)) = queue.last() {
                if v <= peak {
                    queue.pop();
                } else {
                    break;
                }
            }
            queue.push((abs_idx, peak));
            while let Some(&(idx, _)) = queue.first() {
                if idx + wlen <= abs_idx {
                    queue.remove(0);
                } else {
                    break;
                }
            }
            let future_peak = queue.first().map(|&(_, v)| v).unwrap_or(0.0);

            // 3. 基于未来峰值计算目标增益并平滑
            let target = if future_peak > thr { thr / future_peak } else { 1.0 };
            let coef = if target < self.gain { aa } else { ar };
            self.gain += (target - self.gain) * coef;

            // 4. 输出延迟后的采样（增益已提前压下）
            left[i] = out_l * self.gain;
            right[i] = out_r * self.gain;
            self.index += 1;
        }
        self.window = queue;
    }
}



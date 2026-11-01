//! 内置 DSP 引擎：兼容 CamillaDSP YAML 的常用子集。
//!
//! 支持：
//! - filters：Biquad（LowShelf/HighShelf/Peaking/Lowpass/Highpass）、Gain、Delay
//!   （Conv/FIR 依赖服务端本地 wav，客户端按直通处理）
//! - 立体声效果（filters 中声明、pipeline 的 Stereo 阶段执行）：
//!   MsWiden / HaasDelay / Reverb / AutoPan / SoftClip / Flanger / Chorus /
//!   Phaser / Tremolo / SubHarmonic / Limiter —— 见 `audio::effects`
//! - mixers：矩阵映射（立体声拓宽 / 交叉馈送）
//! - pipeline：Filter / Mixer / Stereo 阶段顺序
//!
//! 单用户 HIFI 场景下逐帧处理；NAS 上长卷积的性能上限在 Design.md 第 10 节已说明。

use std::collections::HashMap;

use serde::Deserialize;
use tracing::warn;

use crate::engine::effects::StereoEffect;

#[derive(Debug, Deserialize)]
struct DspConfig {
    #[serde(default)]
    filters: HashMap<String, FilterDef>,
    #[serde(default)]
    mixers: HashMap<String, MixerDef>,
    #[serde(default)]
    pipeline: Vec<Stage>,
}

#[derive(Debug, Deserialize)]
struct FilterDef {
    #[serde(rename = "type")]
    ftype: String,
    #[serde(default)]
    parameters: HashMap<String, serde_yaml::Value>,
}

#[derive(Debug, Deserialize, Clone)]
struct MixerDef {
    mapping: Vec<MixDest>,
}

#[derive(Debug, Deserialize, Clone)]
struct MixDest {
    dest: usize,
    sources: Vec<MixSrc>,
}

#[derive(Debug, Deserialize, Clone)]
struct MixSrc {
    channel: usize,
    #[serde(default)]
    gain: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct Stage {
    #[serde(rename = "type")]
    stype: String,
    #[serde(default)]
    channel: Option<usize>,
    #[serde(default)]
    names: Option<Vec<String>>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    out_channels: Option<usize>,
}

/// 单声道滤波器实例（带状态）。
enum FilterState {
    Biquad {
        b: [f64; 3],
        a: [f64; 3],
        x1: f64,
        x2: f64,
        y1: f64,
        y2: f64,
    },
    Gain(f64),
    Delay {
        ring: Vec<f64>,
        index: usize,
    },
}

impl FilterState {
    fn process_sample(&mut self, x: f64) -> f64 {
        match self {
            FilterState::Biquad { b, a, x1, x2, y1, y2 } => {
                let y = b[0] * x + b[1] * *x1 + b[2] * *x2 - a[1] * *y1 - a[2] * *y2;
                *x2 = *x1;
                *x1 = x;
                *y2 = *y1;
                *y1 = y;
                y
            }
            FilterState::Gain(g) => x * *g,
            FilterState::Delay { ring, index } => {
                let len = ring.len();
                if len == 0 {
                    return x;
                }
                let out = ring[*index];
                ring[*index] = x;
                *index = (*index + 1) % len;
                out
            }
        }
    }
}

struct FilterStage {
    channel: usize,
    state: FilterState,
}

enum ExecStage {
    Filter(Vec<FilterStage>),
    Mixer {
        mapping: Vec<MixDest>,
        out_channels: usize,
    },
    /// 立体声效果（一次处理整块 L/R）。
    Stereo(Box<dyn StereoEffect>),
}

pub struct BuiltinDsp {
    stages: Vec<ExecStage>,
    pub name: String,
}

impl BuiltinDsp {
    /// 从 CamillaDSP YAML 构建处理器。
    /// 空 pipeline（原声纯净）合法；未知滤波器会跳过并记录警告。
    pub fn from_yaml(yaml: &str, sample_rate: u32) -> anyhow::Result<Self> {
        let cfg: DspConfig = serde_yaml::from_str(yaml)?;
        let mut stages = Vec::new();

        for stage in &cfg.pipeline {
            match stage.stype.as_str() {
                "Filter" => {
                    let names = stage.names.clone().unwrap_or_default();
                    let channel = stage.channel.unwrap_or(0);
                    let mut per_channel = Vec::new();
                    for fname in names {
                        let Some(def) = cfg.filters.get(&fname) else {
                            warn!(filter = %fname, "YAML 引用了不存在的滤波器，跳过");
                            continue;
                        };
                        // 立体声效果走 Stereo 阶段。
                        if is_stereo_effect_type(&def.ftype) {
                            warn!(filter = %fname, ftype = %def.ftype,
                                "立体声效果 {fname} 应在 pipeline 的 Stereo 阶段声明，已自动转为 Stereo 阶段");
                            let fx = build_stereo_effect(def, sample_rate)?;
                            stages.push(ExecStage::Stereo(fx));
                            continue;
                        }
                        let state = build_filter(def, sample_rate)?;
                        per_channel.push(FilterStage { channel, state });
                    }
                    if !per_channel.is_empty() {
                        stages.push(ExecStage::Filter(per_channel));
                    }
                }
                "Stereo" => {
                    let names = stage.names.clone().unwrap_or_default();
                    for fname in names {
                        let Some(def) = cfg.filters.get(&fname) else {
                            warn!(filter = %fname, "YAML 引用了不存在的立体声效果，跳过");
                            continue;
                        };
                        if !is_stereo_effect_type(&def.ftype) {
                            warn!(filter = %fname, ftype = %def.ftype,
                                "Stereo 阶段引用了单声道滤波器 {fname}，已按单声道 Filter 处理");
                            let state = build_filter(def, sample_rate)?;
                            stages.push(ExecStage::Filter(vec![FilterStage {
                                channel: stage.channel.unwrap_or(0),
                                state,
                            }]));
                            continue;
                        }
                        let fx = build_stereo_effect(def, sample_rate)?;
                        stages.push(ExecStage::Stereo(fx));
                    }
                }
                "Mixer" => {
                    let Some(name) = &stage.name else {
                        warn!("Mixer 阶段缺少 name，跳过");
                        continue;
                    };
                    let Some(mixer) = cfg.mixers.get(name) else {
                        warn!(mixer = %name, "YAML 引用了不存在的混音器，跳过");
                        continue;
                    };
                    let out_channels = stage
                        .out_channels
                        .unwrap_or_else(|| mixer.mapping.iter().map(|m| m.dest + 1).max().unwrap_or(2));
                    stages.push(ExecStage::Mixer {
                        mapping: mixer.mapping.clone(),
                        out_channels,
                    });
                }
                other => {
                    warn!(stage = %other, "内置 DSP 引擎暂不支持该阶段类型（已跳过）");
                }
            }
        }

        Ok(Self {
            stages,
            name: String::new(),
        })
    }

    /// 处理整段 planar f64 数据（64 位内核，2 声道）。
    pub fn process(&mut self, buffers: &mut crate::engine::pcm::Planar) {
        // 立体声效果需要 2 声道；单声道输入先复制出右声道。
        if buffers.len() == 1 {
            buffers.push(buffers[0].clone());
        }
        for stage in &mut self.stages {
            match stage {
                ExecStage::Filter(per_channel) => {
                    for fs in per_channel.iter_mut() {
                        if fs.channel >= buffers.len() {
                            continue;
                        }
                        for sample in buffers[fs.channel].iter_mut() {
                            *sample = fs.state.process_sample(*sample);
                        }
                    }
                }
                ExecStage::Stereo(fx) => {
                    if buffers.len() >= 2 {
                        let (l, r) = buffers.split_at_mut(1);
                        fx.process(&mut l[0], &mut r[0]);
                    }
                }
                ExecStage::Mixer {
                    mapping,
                    out_channels,
                } => {
                    let frames = buffers.first().map(|b| b.len()).unwrap_or(0);
                    let mut out = vec![vec![0.0f64; frames]; *out_channels];
                    for m in mapping {
                        if m.dest >= *out_channels {
                            continue;
                        }
                        for src in &m.sources {
                            if src.channel >= buffers.len() {
                                continue;
                            }
                            let gain = src.gain.unwrap_or(1.0);
                            for (i, s) in buffers[src.channel].iter().enumerate() {
                                out[m.dest][i] += s * gain;
                            }
                        }
                    }
                    *buffers = out;
                }
            }
        }
    }
}

fn build_filter(def: &FilterDef, sample_rate: u32) -> anyhow::Result<FilterState> {
    let p = &def.parameters;
    let num = |key: &str, default: f64| -> f64 {
        p.get(key).and_then(|v| v.as_f64()).unwrap_or(default)
    };
    let fs = sample_rate as f64;

    match def.ftype.as_str() {
        "Biquad" => {
            let kind = p
                .get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("Peaking");
            let f0 = num("freq", 1000.0);
            let gain_db = num("gain", 0.0);
            let q = num("q", 0.707);
            let (b, a) = biquad_coeffs(kind, f0, fs, gain_db, q);
            Ok(FilterState::Biquad {
                b,
                a,
                x1: 0.0,
                x2: 0.0,
                y1: 0.0,
                y2: 0.0,
            })
        }
        "Gain" => {
            let gain_db = num("gain", 0.0);
            Ok(FilterState::Gain(10f64.powf(gain_db / 20.0)))
        }
        "Delay" => {
            let delay = num("delay", 0.0);
            let unit = p.get("unit").and_then(|v| v.as_str()).unwrap_or("ms");
            let ms = if unit == "samples" {
                delay / fs * 1000.0
            } else {
                delay
            };
            let samples = ((ms / 1000.0) * fs).round() as usize;
            Ok(FilterState::Delay {
                ring: vec![0.0; samples],
                index: 0,
            })
        }
        // 卷积 FIR 依赖服务端本地的 wav 文件，客户端读不到：按直通处理，
        // 同预设里的其它滤波器/混音器仍照常生效。
        "Conv" => Ok(FilterState::Gain(1.0)),
        other => {
            anyhow::bail!("内置 DSP 暂不支持的滤波器类型: {other}")
        }
    }
}

/// 该滤波器类型是否属于立体声效果（走 Stereo 阶段）。
fn is_stereo_effect_type(ftype: &str) -> bool {
    matches!(
        ftype,
        "MsWiden"
            | "HaasDelay"
            | "Reverb"
            | "AutoPan"
            | "SoftClip"
            | "Flanger"
            | "Chorus"
            | "Phaser"
            | "Tremolo"
            | "SubHarmonic"
            | "Limiter"
            | "Gain"
    )
}

/// 从 YAML 滤波器定义构建立体声效果。
fn build_stereo_effect(def: &FilterDef, sample_rate: u32) -> anyhow::Result<Box<dyn StereoEffect>> {
    use crate::engine::effects::*;
    let p = &def.parameters;
    let num = |key: &str, default: f64| -> f64 {
        p.get(key).and_then(|v| v.as_f64()).unwrap_or(default)
    };
    let int = |key: &str, default: usize| -> usize {
        p.get(key)
            .and_then(|v| v.as_i64())
            .map(|v| v.max(1) as usize)
            .unwrap_or(default)
    };

    let fx: Box<dyn StereoEffect> = match def.ftype.as_str() {
        "Gain" => Box::new(Gain::new(num("gain_db", 0.0))),
        "MsWiden" => Box::new(MsWiden::new(num("width", 1.35))),
        "HaasDelay" => Box::new(HaasDelay::new(
            sample_rate,
            num("delay_ms", 12.0),
            num("mix", 1.0),
            num("highpass_hz", 200.0),
        )),
        "Reverb" => Box::new(Freeverb::new(
            sample_rate,
            num("room", 0.6),
            num("damp", 0.4),
            num("wet", 0.3),
            num("width", 1.0),
        )),
        "AutoPan" => Box::new(AutoPan::new(sample_rate, num("rate_hz", 0.1), num("depth", 1.0))),
        "SoftClip" => Box::new(SoftClip::new(
            sample_rate,
            num("drive", 1.5),
            num("mix", 0.3),
            num("highpass_hz", 0.0),
        )),
        "Flanger" => Box::new(Flanger::new(
            sample_rate,
            num("rate_hz", 0.3),
            num("depth_ms", 3.0),
            num("feedback", 0.3),
            num("mix", 0.5),
        )),
        "Chorus" => Box::new(Chorus::new(
            sample_rate,
            num("rate_hz", 0.6),
            num("depth_ms", 2.5),
            int("voices", 3),
            num("mix", 0.45),
        )),
        "Phaser" => Box::new(Phaser::new(
            sample_rate,
            num("rate_hz", 0.4),
            num("depth", 0.7),
            int("stages", 4),
            num("feedback", 0.4),
            num("mix", 0.5),
        )),
        "Tremolo" => Box::new(Tremolo::new(sample_rate, num("rate_hz", 4.0), num("depth", 0.6))),
        "SubHarmonic" => Box::new(SubHarmonic::new(
            sample_rate,
            num("low_hz", 80.0),
            num("high_hz", 160.0),
            num("mix", 0.35),
        )),
        "Limiter" => Box::new(Limiter::new(
            sample_rate,
            num("threshold_db", -1.0),
            num("attack_ms", 2.0),
            num("release_ms", 120.0),
        )),
        other => anyhow::bail!("未知立体声效果类型: {other}"),
    };
    Ok(fx)
}

/// RBJ Audio EQ Cookbook 双二阶系数（归一化 a0 = 1）。
///
/// 架式滤波器（LowShelf/HighShelf）改走 `eq::design_shelf` 的双线性变换构造：
/// 原先的系数表在 Nyquist 处分子为零、分母不为零，架式实际退化成带通
/// （"重低音增强"预设的高频增益被错误压掉）。
fn biquad_coeffs(kind: &str, f0: f64, fs: f64, gain_db: f64, q: f64) -> ([f64; 3], [f64; 3]) {
    let w0 = 2.0 * std::f64::consts::PI * f0 / fs;
    let cos_w = w0.cos();
    let sin_w = w0.sin();
    let alpha = sin_w / (2.0 * q.max(0.0001));
    let a = 10f64.powf(gain_db / 40.0);

    let (b0, b1, b2, a0, a1, a2) = match kind {
        "LowShelf" | "HighShelf" => {
            let high = kind == "HighShelf";
            let sr = fs.round() as u32;
            let c = crate::engine::eq::design_shelf(high, gain_db, q, f0, sr);
            return (
                [c.b0, c.b1, c.b2],
                [1.0, c.a1, c.a2],
            );
        }
        "Peaking" => (
            1.0 + alpha * a,
            -2.0 * cos_w,
            1.0 - alpha * a,
            1.0 + alpha / a,
            -2.0 * cos_w,
            1.0 - alpha / a,
        ),
        "Lowpass" => (
            (1.0 - cos_w) / 2.0,
            1.0 - cos_w,
            (1.0 - cos_w) / 2.0,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        "Highpass" => (
            (1.0 + cos_w) / 2.0,
            -(1.0 + cos_w),
            (1.0 + cos_w) / 2.0,
            1.0 + alpha,
            -2.0 * cos_w,
            1.0 - alpha,
        ),
        // 未知类型按直通处理。
        _ => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
    };

    (
        [b0 / a0, b1 / a0, b2 / a0],
        [1.0, a1 / a0, a2 / a0],
    )
}



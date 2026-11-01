//! 流式处理链：把整段式处理拆成可按块推进的组件。
//!
//! * [`ResampleStream`]：行为与 [`crate::engine::pcm::resample`] 对齐，
//!   输出帧数与整段 `process_all` 一致（误差在 FFT 分块的少量帧内）。
//! * [`BlockChain`]：ReplayGain → DSP → EQ → 交叉馈送 → 淡入淡出，
//!   与 [`crate::engine::pipeline::prepare`] 的第 3–7 步逐样本对齐。

use rubato::Resampler;

use crate::engine::crossfeed::CrossfeedSettings;
use crate::engine::fade;
use crate::engine::pcm::{self, Planar};

/// 本地播放链的处理参数（对应服务端的 ReplayGain → DSP → EQ → 交叉馈送 → 淡入淡出）。
pub struct ChainOptions<'a> {
    /// CamillaDSP 预设 YAML（None / 空 pipeline = 直通）
    pub preset_yaml: Option<&'a str>,
    /// PEQ/GEQ 配置 JSON（None = 不启用）
    pub eq_json: Option<&'a str>,
    /// ReplayGain 线性增益（None / 1.0 = 不调整）
    pub rg_linear: Option<f64>,
    /// 交叉馈送（耳机声像）
    pub crossfeed: CrossfeedSettings,
    /// 曲目淡入/淡出时长（毫秒，0 = 关闭）
    pub fade_in_ms: f64,
    pub fade_out_ms: f64,
}

/// 毫秒（f64，Dart 侧传 double）→ 整数毫秒；负数/NaN 视为 0。
fn ms_u32(ms: f64) -> u32 {
    if !ms.is_finite() || ms <= 0.0 {
        return 0;
    }
    ms.round().clamp(0.0, u32::MAX as f64) as u32
}

/// 空 pipeline 的 YAML 视为直通（与服务端 `pipeline::is_bypass_yaml` 同判据）。
pub fn is_bypass_yaml(yaml: &str) -> bool {
    match serde_yaml::from_str::<serde_yaml::Value>(yaml) {
        Ok(v) => v
            .get("pipeline")
            .and_then(|p| p.as_sequence())
            .map(|s| s.is_empty())
            .unwrap_or(true),
        Err(_) => true,
    }
}

/// 块式重采样：按任意块长喂入 planar f64 PCM，增量产出重采样结果。
pub struct ResampleStream {
    resampler: rubato::Fft<f64>,
    channels: usize,
    pending: Planar,
    /// 启动时丢弃的 FFT 输出延迟帧数。
    skip: usize,
    /// 已喂入的源帧数。
    fed: u64,
    /// 已产出的目标帧数（已扣除 skip）。
    emitted: u64,
    ratio: f64,
}

impl ResampleStream {
    pub fn new(from: u32, to: u32, channels: usize) -> anyhow::Result<Self> {
        let resampler = crate::engine::resampler::make_fft(from, to, channels)?;
        let skip = resampler.output_delay();
        Ok(Self {
            resampler,
            channels,
            pending: vec![Vec::new(); channels],
            skip,
            fed: 0,
            emitted: 0,
            ratio: to as f64 / from as f64,
        })
    }

    pub fn push(&mut self, block: &Planar) -> anyhow::Result<Planar> {
        for c in 0..self.channels {
            self.pending[c].extend_from_slice(&block[c]);
        }
        self.fed += pcm::frames(block) as u64;
        self.drain()
    }

    /// 补零冲刷尾部，并把输出裁剪到理论长度 `ceil(fed * ratio)`。
    ///
    /// 用 `ceil` 而不是 `round`：整段路径走的是 rubato `process_all`，它按
    /// `ceil(ratio * input_len)` 定输出长度（44.1k→48k 的 f64 比值会把精确边界
    /// 顶到 96000.0000001，取整后是 96001）。两边必须同一条取整规则，帧数才对得上。
    pub fn flush(&mut self) -> anyhow::Result<Planar> {
        let expected = (self.fed as f64 * self.ratio).ceil() as u64;
        let mut out = self.drain()?;
        while self.emitted < expected {
            let need = self.resampler.input_frames_next();
            for c in 0..self.channels {
                self.pending[c].resize(need, 0.0);
            }
            let more = self.drain()?;
            if more.iter().all(|c| c.is_empty()) {
                break;
            }
            for (dst, src) in out.iter_mut().zip(more) {
                dst.extend(src);
            }
        }
        let over = self.emitted.saturating_sub(expected) as usize;
        if over > 0 {
            for c in out.iter_mut() {
                let keep = c.len().saturating_sub(over.min(c.len()));
                c.truncate(keep);
            }
            self.emitted -= over as u64;
        }
        Ok(out)
    }

    fn drain(&mut self) -> anyhow::Result<Planar> {
        let mut out: Planar = vec![Vec::new(); self.channels];
        loop {
            let need = self.resampler.input_frames_next();
            if self.pending[0].len() < need {
                break;
            }

            let mut interleaved = Vec::with_capacity(need * self.channels);
            for i in 0..need {
                for c in 0..self.channels {
                    interleaved.push(self.pending[c][i]);
                }
            }
            let input = rubato::audioadapter_buffers::owned::InterleavedOwned::new_from(
                interleaved,
                self.channels,
                need,
            )?;
            let out_len = self.resampler.output_frames_next();
            let mut output = rubato::audioadapter_buffers::owned::InterleavedOwned::new_from(
                vec![0.0f64; out_len * self.channels],
                self.channels,
                out_len,
            )?;
            self.resampler
                .process_into_buffer(&input, &mut output, None)?;
            let data = output.take_data();

            for c in 0..self.channels {
                self.pending[c].drain(..need);
            }
            let drop = self.skip.min(out_len);
            self.skip -= drop;
            for i in drop..out_len {
                for c in 0..self.channels {
                    out[c].push(data[i * self.channels + c]);
                }
            }
            self.emitted += (out_len - drop) as u64;
        }
        Ok(out)
    }
}

/// 块式处理链：ReplayGain → DSP → EQ → 交叉馈送 → 淡入淡出。
///
/// 顺序与整段 [`crate::engine::pipeline::prepare`] 一致；重采样不在这里，
/// 由调用方先用 [`ResampleStream`] 推到输出采样率再喂进来（`rate` 必须是对应
/// 输出采样率，通常是 48000）。
///
/// 淡入淡出按**绝对帧位置**推进，与 `fade::fade_in` / `fade::fade_out` 逐样本等价：
/// 淡入首帧为 0，淡出末帧精确为 0。
pub struct BlockChain {
    gain: Option<f64>,
    dsp: Option<crate::engine::dsp_builtin::BuiltinDsp>,
    eq: Option<crate::engine::eq::EqProcessor>,
    crossfeed: Option<crate::engine::crossfeed::CrossfeedProcessor>,
    fade_in: usize,
    fade_out: usize,
    total_frames: Option<usize>,
    processed: usize,
}

impl BlockChain {
    pub fn new(
        opts: &ChainOptions<'_>,
        rate: u32,
        total_frames: Option<usize>,
    ) -> anyhow::Result<Self> {
        // 空 pipeline 的 YAML 视为直通，不建 DSP（与整段路径同判据）。
        let dsp = match opts.preset_yaml {
            Some(yaml) if !is_bypass_yaml(yaml) => {
                Some(crate::engine::dsp_builtin::BuiltinDsp::from_yaml(yaml, rate)?)
            }
            _ => None,
        };
        // EQ 先解析 profile，只有真正有条带时才建处理器；
        // 声道数固定 2：整段路径在 EQ 之前已 `pcm::align_channels`。
        let eq = match opts.eq_json {
            Some(json) => {
                let profile = crate::engine::eq::EqProfile::from_json(json)?;
                if profile.is_active() {
                    Some(crate::engine::eq::EqProcessor::new(&profile, rate, 2)?)
                } else {
                    None
                }
            }
            None => None,
        };
        let crossfeed = if opts.crossfeed.is_active() {
            Some(crate::engine::crossfeed::CrossfeedProcessor::new(rate, &opts.crossfeed))
        } else {
            None
        };
        Ok(Self {
            gain: opts.rg_linear,
            dsp,
            eq,
            crossfeed,
            // 与整段路径共用 `fade::ms_to_frames`（含上限钳制与 0ms = 关闭）。
            fade_in: fade::ms_to_frames(rate, ms_u32(opts.fade_in_ms)),
            fade_out: fade::ms_to_frames(rate, ms_u32(opts.fade_out_ms)),
            total_frames,
            processed: 0,
        })
    }

    pub fn process(&mut self, mut block: Planar) -> Planar {
        if let Some(gain) = self.gain {
            pcm::apply_gain(&mut block, gain);
        }
        if let Some(dsp) = self.dsp.as_mut() {
            dsp.process(&mut block);
        }
        if let Some(eq) = self.eq.as_mut() {
            eq.process(&mut block);
        }
        if let Some(crossfeed) = self.crossfeed.as_mut() {
            crossfeed.process(&mut block);
        }

        let frames = pcm::frames(&block);
        if frames > 0 {
            // 淡入：长度不得超过总帧数（否则整首都会被压低）。
            let fade_in = (self.fade_in > 0)
                .then(|| self.fade_in.min(self.total_frames.unwrap_or(self.fade_in)));
            // 淡出：总帧数未知时不做（流式不知道终点）。
            let fade_out = match self.total_frames {
                Some(total) if self.fade_out > 0 => {
                    let n = self.fade_out.min(total);
                    (n > 0).then_some((n, total - n))
                }
                _ => None,
            };

            if fade_in.is_some() || fade_out.is_some() {
                for i in 0..frames {
                    let pos = self.processed + i;
                    let mut g = 1.0;
                    if let Some(n) = fade_in {
                        if pos < n {
                            g *= pos as f64 / n as f64;
                        }
                    }
                    if let Some((n, start)) = fade_out {
                        if pos >= start {
                            let last = (n - 1).max(1) as f64;
                            g *= (last - (pos - start) as f64) / last;
                        }
                    }
                    if g != 1.0 {
                        for ch in block.iter_mut() {
                            if let Some(s) = ch.get_mut(i) {
                                *s *= g;
                            }
                        }
                    }
                }
            }
        }
        self.processed += frames;
        block
    }

    /// seek 后把绝对帧位置对齐到目标点（淡入淡出按新位置继续）。
    ///
    /// 滤波器/延迟线的内部状态不做重建：seek 是一次新的听感起点，
    /// 保持状态能避免重建 DSP 的开销；需要彻底重置时用
    /// [`BlockChain::rebuild`]。
    pub fn reset_position(&mut self, frames: usize) {
        self.processed = frames;
    }
}



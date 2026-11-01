//! rubato 5 重采样与声道对齐：**f64 内核、目标采样率可配置**。
//!
//! 与旧实现的区别：
//! - 数据从 f32 升为 f64（Hi-Res + 深 EQ 提升不再提前损失精度）；
//! - 目标采样率不再是硬编码 48kHz：无损档保留源采样率（44.1k/88.2k/96k/192k…），
//!   仅在 Opus（有 48k 上限）或显式指定时才重采样；
//! - 采样率相同直接零成本直通，不引入任何滤波误差。

use crate::engine::pcm::{self, Planar};

/// Opus 编码上限采样率。
pub const OPUS_SAMPLE_RATE: u32 = 48_000;
const RESAMPLE_CHUNK: usize = 1024;

/// 构造与 [`prepare`] 完全一致的 rubato FFT 重采样器。
pub fn make_fft(from: u32, to: u32, channels: usize) -> anyhow::Result<rubato::Fft<f64>> {
    Ok(rubato::Fft::<f64>::new(
        from as usize,
        to as usize,
        RESAMPLE_CHUNK,
        channels,
        rubato::FixedSync::Both,
    )?)
}

/// 准备解码结果：声道对齐 + 按需重采样到 `target`（None = 保留源采样率）。
///
/// 声道数直接看缓冲长度（`pcm::align_channels` 幂等），不额外接收 channels 参数——
/// 早期两处调用各传一次声道数，导致立体声被当成单声道又补一通道（输出 3 声道 FLAC）。
pub fn prepare(
    decoded: Planar,
    sample_rate: u32,
    target: Option<u32>,
) -> anyhow::Result<Prepared> {
    let mut planar = decoded;
    pcm::align_channels(&mut planar);
    let target_rate = target.unwrap_or(sample_rate);
    let planar = if target_rate == sample_rate {
        planar
    } else {
        resample_with(make_fft(sample_rate, target_rate, planar.len())?, &planar)?
    };
    Ok(Prepared {
        planar,
        sample_rate: target_rate,
        resampled: target_rate != sample_rate,
    })
}

/// 重采样结果。
pub struct Prepared {
    pub planar: Planar,
    pub sample_rate: u32,
    /// 是否真的重采样过（false = 原生直通，可标 bit-perfect）。
    pub resampled: bool,
}


/// 旧接口：重采样到 48kHz 立体声 planar f32（仅供遗留调用点）。
#[allow(dead_code)]
pub fn resample_to_target(
    interleaved: Vec<f32>,
    sample_rate: u32,
    channels: u16,
) -> anyhow::Result<Vec<Vec<f32>>> {
    let planar = pcm::interleaved_f32_to_planar_f64(&interleaved, channels as usize);
    let mut planar = planar;
    pcm::align_channels(&mut planar);
    let planar = if sample_rate == OPUS_SAMPLE_RATE {
        planar
    } else {
        pcm::resample(planar, sample_rate, OPUS_SAMPLE_RATE)?
    };
    Ok(planar
        .into_iter()
        .map(|c| c.into_iter().map(|s| s as f32).collect())
        .collect())
}

fn resample_with<T: rubato::Resampler<f64>>(mut resampler: T, planar: &Planar) -> anyhow::Result<Planar> {
    let ch = planar.len();
    let n = pcm::frames(planar);
    let mut interleaved: Vec<f64> = Vec::with_capacity(n * ch);
    for i in 0..n {
        for c in planar {
            interleaved.push(c[i]);
        }
    }
    let input = rubato::audioadapter_buffers::owned::InterleavedOwned::new_from(interleaved, ch, n)?;
    let output = resampler.process_all(&input, n, None)?;
    let out = output.take_data();
    let out_frames = out.len() / ch;
    let mut result: Planar = vec![Vec::with_capacity(out_frames); ch];
    for c in 0..ch {
        result[c].extend(out[c..].iter().step_by(ch).copied());
    }
    Ok(result)
}



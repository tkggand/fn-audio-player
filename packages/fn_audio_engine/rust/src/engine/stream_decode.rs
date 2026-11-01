//! 块式解码：按 packet 边界增量产出 planar f64 PCM，可 seek。
//!
//! 与 `audio::stream_decode`（服务端）一致：已做立体声对齐（单声道复制为双声道，
//! 多声道只取前两声道），采样值为 f64。输入换成任意 [`MediaSource`]（App 的路上
//! 是 HTTP Range 源），因此可在不落地整首文件的前提下边下边播。

use symphonia::core::codecs::audio::{AudioDecoder, AudioDecoderOptions};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::{FormatReader, SeekMode, SeekTo};
use symphonia::core::io::MediaSource;
use symphonia::core::units::Time;

use crate::engine::decoder::open_media;
use crate::engine::pcm::Planar;

/// 立体声对齐后的输出声道数。
const OUT_CHANNELS: usize = 2;

pub struct StreamDecoder {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn AudioDecoder>,
    track_id: u32,
    sample_rate: u32,
    channels: usize,
    total_frames: Option<u64>,
}

impl StreamDecoder {
    pub fn open(source: Box<dyn MediaSource>, hint_ext: Option<&str>) -> anyhow::Result<Self> {
        let media = open_media(source, hint_ext)?;
        let decoder = crate::engine::decoder::codec_registry()
            .make_audio_decoder(&media.codec_params, &AudioDecoderOptions::default())?;
        Ok(Self {
            format: media.format,
            decoder,
            track_id: media.track_id,
            sample_rate: media.sample_rate,
            channels: OUT_CHANNELS,
            total_frames: media.total_frames,
        })
    }

    pub fn sample_rate(&self) -> u32 {
        self.sample_rate
    }

    pub fn channels(&self) -> usize {
        self.channels
    }

    pub fn total_frames(&self) -> Option<u64> {
        self.total_frames
    }

    /// 时长（秒）；容器未给出总帧数时为 None（由 UI 回退到曲库元数据）。
    pub fn duration_secs(&self) -> Option<f64> {
        self.total_frames
            .map(|f| f as f64 / self.sample_rate as f64)
            .filter(|s| *s > 0.0)
    }

    pub fn seek_secs(&mut self, secs: f64) -> anyhow::Result<()> {
        let time = Time::from_millis_u64((secs.max(0.0) * 1000.0).round() as u64);
        self.format.seek(
            SeekMode::Accurate,
            SeekTo::Time {
                time,
                track_id: Some(self.track_id),
            },
        )?;
        self.decoder.reset();
        Ok(())
    }

    /// 返回下一个 PCM 块；块长可能略超 `max_frames`（按 packet 边界），EOF 返回 None。
    pub fn next_block(&mut self, max_frames: usize) -> anyhow::Result<Option<Planar>> {
        let mut out: Planar = vec![Vec::new(); self.channels];
        while out[0].len() < max_frames {
            let packet = match self.format.next_packet() {
                Ok(Some(p)) => p,
                Ok(None) => break,
                Err(SymError::ResetRequired) => continue,
                Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    break;
                }
                Err(e) => return Err(e.into()),
            };
            if packet.track_id != self.track_id {
                continue;
            }
            let decoded = match self.decoder.decode(&packet) {
                Ok(d) => d,
                Err(SymError::DecodeError(_)) => continue,
                Err(SymError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    break;
                }
                Err(e) => return Err(e.into()),
            };
            let pkt_ch = decoded.spec().channels().count().max(1);
            let mut interleaved: Vec<f32> = Vec::new();
            decoded.copy_to_vec_interleaved::<f32>(&mut interleaved);
            let frames = interleaved.len() / pkt_ch;
            for i in 0..frames {
                for c in 0..self.channels {
                    // 单声道复制到两个平面；多声道只取前两声道。
                    let src = if pkt_ch == 1 { 0 } else { c.min(pkt_ch - 1) };
                    out[c].push(interleaved[i * pkt_ch + src] as f64);
                }
            }
        }
        if out.iter().all(|c| c.is_empty()) {
            Ok(None)
        } else {
            Ok(Some(out))
        }
    }
}

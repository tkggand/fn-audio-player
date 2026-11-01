//! DSD（DSF/DFF）流式解码：HTTP Range 源 → 两级抽取 → planar f64 PCM。
//!
//! symphonia 不解 DSD（1 bit 流），因此这里复用与服务端同源的
//! [`DsdReader`] + [`DsdToPcm`]；区别是数据源换成 [`MediaSource`]，
//! 可按时间 seek（对齐到 DSF 块边界）。

use symphonia::core::io::MediaSource;

use crate::engine::dsd::{DsdInfo, DsdReader};
use crate::engine::dsd_pcm::DsdToPcm;
use crate::engine::pcm::Planar;

pub struct DsdStreamDecoder {
    reader: DsdReader<Box<dyn MediaSource>>,
    conv: DsdToPcm,
    info: DsdInfo,
    out_rate: u32,
    raw: Vec<u8>,
    pending: Planar,
    eof: bool,
}

impl DsdStreamDecoder {
    pub fn open(source: Box<dyn MediaSource>) -> anyhow::Result<Self> {
        let mut source = source;
        let info = crate::engine::dsd::parse_reader(&mut source)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        let reader = DsdReader::from_reader(source, info.clone())
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        let channels = info.channel_count();
        let conv = DsdToPcm::with_output_rate(channels, info.sample_rate, info.sample_rate / 64);
        let out_rate = conv.output_rate();
        Ok(Self {
            reader,
            conv,
            info,
            out_rate,
            raw: Vec::new(),
            pending: vec![Vec::new(); 2],
            eof: false,
        })
    }

    pub fn sample_rate(&self) -> u32 {
        self.out_rate
    }

    pub fn duration_secs(&self) -> Option<f64> {
        let d = self.info.duration_secs();
        (d > 0.0).then_some(d)
    }

    pub fn seek_secs(&mut self, secs: f64) -> anyhow::Result<()> {
        self.reader
            .seek_secs(secs)
            .map_err(|e| anyhow::anyhow!("{e}"))?;
        // 抽取滤波器带状态：seek 后重建，避免残影把新位置的开头糊掉。
        self.conv = DsdToPcm::with_output_rate(
            self.info.channel_count(),
            self.info.sample_rate,
            self.out_rate,
        );
        self.pending = vec![Vec::new(); 2];
        self.eof = false;
        Ok(())
    }

    /// 产出至少 `max_frames` 帧（或读到尾部）。
    pub fn next_block(&mut self, max_frames: usize) -> anyhow::Result<Option<Planar>> {
        while !self.eof && self.pending[0].len() < max_frames {
            let more = self
                .reader
                .next_block(&mut self.raw)
                .map_err(|e| anyhow::anyhow!("{e}"))?;
            if !more {
                self.eof = true;
                let mut tail: Planar = vec![Vec::new(); self.info.channel_count()];
                self.conv.flush(&mut tail);
                append_aligned(&mut self.pending, &tail);
                break;
            }
            let mut out: Planar = vec![Vec::new(); self.info.channel_count()];
            self.conv
                .push_bytes(&self.raw, self.info.lsb_first, &mut out);
            append_aligned(&mut self.pending, &out);
        }
        if self.pending[0].is_empty() {
            return Ok(None);
        }
        let n = self.pending[0].len().min(max_frames);
        let mut block: Planar = vec![Vec::with_capacity(n); 2];
        for (dst, src) in block.iter_mut().zip(self.pending.iter_mut()) {
            let tail = src.split_off(n);
            dst.extend_from_slice(src);
            *src = tail;
        }
        Ok(Some(block))
    }
}

/// 把转换出的多声道结果对齐成两声道（单声道复制，多声道取前两路）。
fn append_aligned(dst: &mut Planar, src: &Planar) {
    let frames = src.iter().map(|c| c.len()).min().unwrap_or(0);
    let ch = src.len();
    for i in 0..frames {
        dst[0].push(src[0][i]);
        dst[1].push(if ch <= 1 { src[0][i] } else { src[1][i] });
    }
}

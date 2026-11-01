//! DSD 容器解析：DSF（Sony）与 DFF/DSDIFF（DSD 录音室）。
//!
//! 两种容器都不压缩，只差三件事：字节序、块头、以及位序。
//!
//! | | DSF | DFF (DSDIFF) |
//! |---|---|---|
//! | 幻数 | `DSD ` (28B) + `fmt ` (52B) + `data` | `FRM8` + `DSD ` + `PROP/SND` + `DSD ` |
//! | 整数 | 小端 | 大端（IFF） |
//! | 位序 | **LSB first** | **MSB first** |
//! | 数据 | 定长块 + 每块 12 字节块头 | 单块连续 |
//!
//! ## 为什么自己写
//!
//! symphonia 不解 DSD（它是 1 bit 流，不是 PCM），而 DSF/DFF 的头解析本身很短：
//! 找到采样率、声道数、数据起点，剩下就是顺序读。引一个解 DSD 的库反而更重，
//! 还得处理 DST 压缩（SACD 的有损封装）这种我们**不做**的分支——
//! 遇到 DST 直接报错，比"解出一地碎片"诚实。
//!
//! ## DST 一律拒绝
//!
//! `CMPR` 说自己是 `DST ` 就拒绝：不假装能解，也不输出噪声。
//! 只有 `DSD `（未压缩）才继续。

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

/// DSD 容器解析结果。
#[derive(Debug, Clone, PartialEq)]
pub struct DsdInfo {
    pub channels: u32,
    /// DSD 采样率（Hz）：DSD64 = 2 822 400，DSD128 = 5 644 800……
    pub sample_rate: u32,
    /// 每字节的位序：DSF 是 LSB first，DFF 是 MSB first。
    pub lsb_first: bool,
    /// 数据在文件里的起点。
    pub data_offset: u64,
    /// 数据字节数。
    pub data_size: u64,
    /// DSF 的块长（DFF 无意义，取 0）。
    pub block_size: u32,
    /// 容器名（展示用）。
    pub container: &'static str,
}

impl DsdInfo {
    /// 声道数（受 usize 转换保护）。
    pub fn channel_count(&self) -> usize {
        self.channels as usize
    }

    /// 每声道比特数（= 数据字节 × 8 / 声道）。
    pub fn bits_per_channel(&self) -> u64 {
        if self.channels == 0 {
            0
        } else {
            self.data_size * 8 / self.channels as u64
        }
    }

    /// 时长（秒）。
    pub fn duration_secs(&self) -> f64 {
        let bits = self.bits_per_channel();
        if self.sample_rate == 0 || bits == 0 {
            0.0
        } else {
            bits as f64 / self.sample_rate as f64
        }
    }
}

/// 解析错误（面向用户，直接进日志）。
#[derive(Debug, Clone, PartialEq)]
pub enum DsdError {
    Io(String),
    /// 不是 DSD 文件（幻数不对）。
    NotDsd,
    /// 是 DSD 但用了不支持的压缩（DST）。
    Unsupported(String),
    /// 头部字段不合理。
    Invalid(String),
}

impl std::fmt::Display for DsdError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DsdError::Io(e) => write!(f, "DSD 文件读取失败: {e}"),
            DsdError::NotDsd => write!(f, "不是 DSD 文件"),
            DsdError::Unsupported(what) => write!(f, "不支持的 DSD 格式: {what}"),
            DsdError::Invalid(e) => write!(f, "DSD 头部无效: {e}"),
        }
    }
}

impl std::error::Error for DsdError {}

fn io<E: std::fmt::Display>(e: E) -> DsdError {
    DsdError::Io(e.to_string())
}

/// 判断文件头是不是 DSD（不完整解析，用于快速分派）。
pub fn is_dsd(path: &Path) -> bool {
    let mut f = match File::open(path) {
        Ok(f) => f,
        Err(_) => return false,
    };
    let mut magic = [0u8; 4];
    matches!(f.read_exact(&mut magic), Ok(())) && (&magic == b"DSD " || &magic == b"FRM8")
}

/// 解析 DSD 文件（按幻数分派 DSF / DFF）。
pub fn parse(path: &Path) -> Result<DsdInfo, DsdError> {
    let mut f = File::open(path).map_err(io)?;
    parse_reader(&mut f)
}

/// 解析任意可 seek 数据源（App 走 HTTP Range 源，不落地整首 DSD）。
pub fn parse_reader<R: Read + Seek>(f: &mut R) -> Result<DsdInfo, DsdError> {
    let mut magic = [0u8; 4];
    f.read_exact(&mut magic).map_err(io)?;
    match &magic {
        b"DSD " => {
            // 读幻数后游标已前进 4 字节，分派前回到数据源开头。
            f.seek(SeekFrom::Start(0)).map_err(io)?;
            parse_dsf(f)
        }
        b"FRM8" => {
            f.seek(SeekFrom::Start(0)).map_err(io)?;
            parse_dff(f)
        }
        _ => Err(DsdError::NotDsd),
    }
}

// ---------------------------------------------------------------- DSF

fn rd_u32_le(b: &[u8]) -> u32 {
    u32::from_le_bytes([b[0], b[1], b[2], b[3]])
}

fn rd_u64_le(b: &[u8]) -> u64 {
    u64::from_le_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]])
}

fn rd_u32_be(b: &[u8]) -> u32 {
    u32::from_be_bytes([b[0], b[1], b[2], b[3]])
}

fn rd_u16_be(b: &[u8]) -> u16 {
    u16::from_be_bytes([b[0], b[1]])
}

fn rd_u64_be(b: &[u8]) -> u64 {
    u64::from_be_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]])
}

fn parse_dsf<R: Read + Seek>(f: &mut R) -> Result<DsdInfo, DsdError> {
    // DSD chunk (28 B)
    let mut dsd = [0u8; 28];
    f.read_exact(&mut dsd).map_err(io)?;
    if rd_u64_le(&dsd[4..12]) != 28 {
        return Err(DsdError::Invalid("DSD chunk 大小不是 28".into()));
    }
    // 总文件大小与元数据偏移只是参考值，不参与解析。

    // fmt chunk (52 B)
    let mut fmt = [0u8; 52];
    f.read_exact(&mut fmt).map_err(io)?;
    if &fmt[0..4] != b"fmt " {
        return Err(DsdError::Invalid("缺少 fmt chunk".into()));
    }
    if rd_u64_le(&fmt[4..12]) != 52 {
        return Err(DsdError::Invalid("fmt chunk 大小不是 52".into()));
    }
    let format_id = rd_u32_le(&fmt[16..20]);
    if format_id != 0 {
        return Err(DsdError::Unsupported(format!("DSF format id {format_id}")));
    }
    let channels = rd_u32_le(&fmt[24..28]);
    let sample_rate = rd_u32_le(&fmt[28..32]);
    let bits_per_sample = rd_u32_le(&fmt[32..36]);
    let block_size = rd_u32_le(&fmt[44..48]);
    if bits_per_sample != 1 {
        return Err(DsdError::Invalid(format!(
            "bits_per_sample 应为 1，实际 {bits_per_sample}"
        )));
    }
    validate_common(channels, sample_rate, Some(block_size))?;

    // data chunk 头（12 B：magic + 大小），数据紧跟其后。
    let mut data = [0u8; 12];
    f.read_exact(&mut data).map_err(io)?;
    if &data[0..4] != b"data" {
        return Err(DsdError::Invalid("缺少 data chunk".into()));
    }
    let data_size = rd_u64_le(&data[4..12]).saturating_sub(12);
    let data_offset = f.stream_position().map_err(io)?;

    Ok(DsdInfo {
        channels,
        sample_rate,
        lsb_first: true,
        data_offset,
        data_size,
        block_size,
        container: "DSF",
    })
}

// ---------------------------------------------------------------- DFF

/// IFF 规定的偶数字节对齐：奇数长度补一个 0。
fn padded(size: u64) -> u64 {
    size + (size & 1)
}

fn parse_dff<R: Read + Seek>(f: &mut R) -> Result<DsdInfo, DsdError> {
    // FRM8 头（12 B）："FRM8" + 大小；紧随其后的 4 字节才是表单类型。
    let mut frm8 = [0u8; 12];
    f.read_exact(&mut frm8).map_err(io)?;
    let mut form_type = [0u8; 4];
    f.read_exact(&mut form_type).map_err(io)?;
    if &form_type != b"DSD " {
        return Err(DsdError::NotDsd);
    }

    let mut sample_rate = None;
    let mut channels = None;
    let mut compression = String::from("DSD ");
    let mut data_offset = None;
    let mut data_size = None;

    loop {
        let pos = f.stream_position().map_err(io)?;
        let mut head = [0u8; 12];
        if f.read_exact(&mut head).is_err() {
            break; // 到文件尾：数据块总在 PROP 之后，但坏文件也可能没有。
        }
        let id = [head[0], head[1], head[2], head[3]];
        let size = rd_u64_be(&head[4..12]);

        match &id {
            b"PROP" => {
                let mut prop_type = [0u8; 4];
                f.read_exact(&mut prop_type).map_err(io)?;
                if &prop_type != b"SND " {
                    // 非声音属性（标题、艺术家…）：整块跳过。
                    let skip = size.saturating_sub(4);
                    f.seek(SeekFrom::Current(skip as i64)).map_err(io)?;
                    continue;
                }
                let prop_end = pos + 12 + size;
                while f.stream_position().map_err(io)? < prop_end {
                    let mut sub = [0u8; 12];
                    if f.read_exact(&mut sub).is_err() {
                        break;
                    }
                    let sub_id = [sub[0], sub[1], sub[2], sub[3]];
                    let sub_size = rd_u64_be(&sub[4..12]);
                    let occupy = padded(sub_size);
                    match &sub_id {
                        b"FS  " => {
                            let mut v = [0u8; 4];
                            f.read_exact(&mut v).map_err(io)?;
                            sample_rate = Some(rd_u32_be(&v));
                            skip_extra(f, occupy.saturating_sub(4))?;
                        }
                        b"CHNL" => {
                            let mut v = [0u8; 2];
                            f.read_exact(&mut v).map_err(io)?;
                            channels = Some(rd_u16_be(&v) as u32);
                            // 后面是每个声道的 ID 串。
                            skip_extra(f, occupy.saturating_sub(2))?;
                        }
                        b"CMPR" => {
                            let mut v = [0u8; 4];
                            f.read_exact(&mut v).map_err(io)?;
                            compression =
                                String::from_utf8_lossy(&v).trim_end().to_string();
                            skip_extra(f, occupy.saturating_sub(4))?;
                        }
                        _ => {
                            f.seek(SeekFrom::Current(occupy as i64)).map_err(io)?;
                        }
                    }
                }
            }
            b"DSD " => {
                data_offset = Some(pos + 12);
                data_size = Some(size);
                break;
            }
            b"DST " => {
                // chunk ID 本身就是证据；CMPR 只是声明，还可能缺失或撒谎。
                compression = "DST".to_string();
                data_offset = Some(pos + 12);
                data_size = Some(size);
                break;
            }
            _ => {
                f.seek(SeekFrom::Current(padded(size) as i64)).map_err(io)?;
            }
        }
    }

    // DST 是有损封装（SACD），不解：宁可报错，也不要输出噪声。
    if compression.starts_with("DST") {
        return Err(DsdError::Unsupported(
            "DST 压缩（DST Sound Data），需要 DST 解码器".into(),
        ));
    }
    if compression != "DSD " && !compression.is_empty() && compression != "DSD" {
        return Err(DsdError::Unsupported(format!(
            "压缩类型 '{compression}'，只支持未压缩 DSD"
        )));
    }

    let channels = channels.ok_or_else(|| DsdError::Invalid("缺少 CHNL".into()))?;
    let sample_rate = sample_rate.ok_or_else(|| DsdError::Invalid("缺少 FS".into()))?;
    validate_common(channels, sample_rate, None)?;
    let data_offset = data_offset.ok_or_else(|| DsdError::Invalid("缺少 DSD 数据块".into()))?;
    let data_size = data_size.ok_or_else(|| DsdError::Invalid("缺少 DSD 数据块大小".into()))?;

    Ok(DsdInfo {
        channels,
        sample_rate,
        lsb_first: false,
        data_offset,
        data_size,
        block_size: 0,
        container: "DFF",
    })
}

fn skip_extra<R: Read + Seek>(f: &mut R, n: u64) -> Result<(), DsdError> {
    if n > 0 {
        f.seek(SeekFrom::Current(n as i64)).map_err(io)?;
    }
    Ok(())
}

fn validate_common(channels: u32, sample_rate: u32, block_size: Option<u32>) -> Result<(), DsdError> {
    if channels == 0 || channels > 8 {
        return Err(DsdError::Invalid(format!("声道数 {channels} 不合理")));
    }
    if !(2_000_000..=50_000_000).contains(&sample_rate) {
        return Err(DsdError::Invalid(format!(
            "DSD 采样率 {sample_rate} 不在合理范围"
        )));
    }
    // 块长只有 DSF 有（数据被切成定长块）；DFF 是单块连续，块长为 0 是正常的。
    if block_size == Some(0) {
        return Err(DsdError::Invalid("块长为 0".into()));
    }
    Ok(())
}

// ---------------------------------------------------------------- 读取

/// DSD 数据分块读取器（DSF 剥块头，DFF 直接顺序读）。
pub struct DsdReader<R: Read + Seek> {
    f: R,
    info: DsdInfo,
    /// 下一个块还剩多少字节。
    remaining: u64,
    /// DSF：当前块读完后的 12 字节块头要不要吃掉。
    pending_block_header: bool,
    /// 已消费的每声道字节数（seek 计算用）。
    consumed_per_channel: u64,
}

impl DsdReader<File> {
    pub fn open(path: &Path) -> Result<Self, DsdError> {
        let info = parse(path)?;
        let f = File::open(path).map_err(io)?;
        Self::from_reader(f, info)
    }
}

impl<R: Read + Seek> DsdReader<R> {
    /// 用已解析的信息包装一个数据源（HTTP Range 源），游标跳到数据起点。
    pub fn from_reader(mut f: R, info: DsdInfo) -> Result<Self, DsdError> {
        // 必须跳到数据起点：头部占几十到几千字节，直接从 0 读会把头部当音频。
        f.seek(SeekFrom::Start(info.data_offset)).map_err(io)?;
        let remaining = info.data_size;
        let pending_block_header = info.block_size > 0;
        Ok(Self {
            f,
            info,
            remaining,
            pending_block_header,
            consumed_per_channel: 0,
        })
    }

    /// 容器信息（解析结果）。
    pub fn info(&self) -> &DsdInfo {
        &self.info
    }

    /// 按时间 seek（秒），对齐到 DSF 块边界 / DFF 字节边界。
    ///
    /// DSF 的块内偏移会向下取整到整块（默认 4096 B/声道 ≈ 11.6 ms），
    /// 这比逐字节重算块头更稳；听感上 ~10 ms 的误差不可察觉。
    pub fn seek_secs(&mut self, secs: f64) -> Result<(), DsdError> {
        let dsd_rate = self.info.sample_rate as f64;
        let channels = self.info.channels as u64;
        let mut per_channel = ((secs.max(0.0) * dsd_rate) / 8.0).round() as u64;
        let max_bytes = self.info.data_size / channels.max(1);
        per_channel = per_channel.min(max_bytes);

        let offset = if self.info.block_size > 0 {
            let block = self.info.block_size as u64;
            per_channel -= per_channel % block;
            let block_index = per_channel / block;
            let intra = per_channel % block;
            // DSF：每块 = 每声道 block_size 字节 + 12 字节块头，声道字节交错。
            self.info.data_offset
                + block_index * (block * channels + 12)
                + intra * channels
        } else {
            // DFF：单块连续，按声道交错。
            self.info.data_offset + per_channel * channels
        };

        self.f.seek(SeekFrom::Start(offset)).map_err(io)?;
        self.consumed_per_channel = per_channel;
        self.remaining = self.info.data_size - per_channel * channels;
        self.pending_block_header = self.info.block_size > 0;
        Ok(())
    }

    /// 读下一块原始 DSD 字节（不含块头）。到文件尾返回空。
    pub fn next_block(&mut self, buf: &mut Vec<u8>) -> Result<bool, DsdError> {
        if self.remaining == 0 {
            return Ok(false);
        }
        let channels = self.info.channels.max(1) as u64;
        let want = if self.info.block_size > 0 {
            // DSF：每声道 block_size 字节，整块 = block_size × channels。
            self.info.block_size as u64 * channels
        } else {
            self.remaining
        };
        let n = want.min(self.remaining) as usize;
        buf.clear();
        buf.resize(n, 0);
        let mut read = 0usize;
        while read < n {
            match self.f.read(&mut buf[read..]) {
                Ok(0) => break,
                Ok(k) => read += k,
                Err(e) => return Err(io(e)),
            }
        }
        buf.truncate(read);
        self.remaining -= read as u64;
        self.consumed_per_channel += read as u64 / channels;
        if self.remaining == 0 {
            // 末块之后没有块头。
            self.pending_block_header = false;
        } else if self.info.block_size > 0 && self.pending_block_header {
            // 吃掉 12 字节块头（1 字节填充 + u24 块长 + i64 指针）。
            let mut skip = [0u8; 12];
            self.f.read_exact(&mut skip).map_err(io)?;
        }
        Ok(read > 0)
    }
}

/// 反转一个字节的位序（DSF LSB-first ↔ DFF MSB-first 互转）。
#[inline]
pub fn reverse_bits(b: u8) -> u8 {
    b.reverse_bits()
}



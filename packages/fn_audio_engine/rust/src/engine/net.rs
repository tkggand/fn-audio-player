//! HTTP Range 音频源：把 `GET /api/stream/{id}?bypass=1` 的原始文件当作
//! 可 seek 的 [`MediaSource`]，按块按需拉取（滑动窗口缓存），不落地整首文件。
//!
//! 服务端在 bypass 模式下以文件流响应原始字节并支持 `Range`，因此拖动进度条
//! 只需一个新的 Range 请求；命中前 App 只保留最近一块数据，内存占用恒定。

use std::io::{self, Read, Seek, SeekFrom};
use std::time::Duration;

use symphonia::core::io::MediaSource;

/// 单次拉取的字节数（64 KiB，约 0.1–0.2 秒的 FLAC）。
const CHUNK: u64 = 64 * 1024;

pub struct HttpMediaSource {
    url: String,
    /// 文件总长（首次 Range 响应里的 `Content-Range` 得到）。
    len: Option<u64>,
    /// 当前逻辑读取位置（文件绝对偏移）。
    pos: u64,
    /// 滑动窗口：`cache_start..cache_start + cache.len()` 是文件的有效字节。
    cache: Vec<u8>,
    cache_start: u64,
    /// 是否支持 Range（首发响应为 206）；不支持时只能顺序读，seek 退化为重开。
    range_ok: bool,
}

impl HttpMediaSource {
    /// 打开 URL 并预取首块。返回错误时（网络/鉴权/404）由上层回退到 just_audio。
    pub fn open(url: &str) -> io::Result<Self> {
        let mut src = Self {
            url: url.to_string(),
            len: None,
            pos: 0,
            cache: Vec::new(),
            cache_start: 0,
            range_ok: false,
        };
        src.fetch(0)?;
        Ok(src)
    }

    pub fn total_len(&self) -> Option<u64> {
        self.len
    }

    /// 拉取从 `start` 开始的一块数据到缓存。
    fn fetch(&mut self, start: u64) -> io::Result<()> {
        let end = start + CHUNK - 1;
        let resp = ureq::get(&self.url)
            .set("Range", &format!("bytes={start}-{end}"))
            .timeout(Duration::from_secs(20))
            .call();
        let resp = match resp {
            Ok(r) => r,
            // 416：请求范围超出文件末尾（读到尾部），视为空块。
            Err(ureq::Error::Status(416, _)) => {
                self.cache.clear();
                self.cache_start = start;
                return Ok(());
            }
            Err(ureq::Error::Status(code, _)) => {
                return Err(io::Error::other(format!("HTTP {code}")));
            }
            Err(e) => return Err(io::Error::other(format!("网络错误: {e}"))),
        };

        let status = resp.status();
        if status == 206 {
            self.range_ok = true;
            if let Some(cr) = resp.header("Content-Range") {
                // Content-Range: bytes 0-65535/12345
                if let Some(total) = cr.rsplit('/').next().and_then(|s| s.trim().parse().ok()) {
                    self.len = Some(total);
                }
            }
        } else if status == 200 {
            // 服务端忽略了 Range（首次转码等）：只能顺序读，长度可从此头得知。
            self.range_ok = false;
            if let Some(cl) = resp.header("Content-Length") {
                self.len = cl.trim().parse().ok();
            }
        }

        let mut bytes = Vec::with_capacity(CHUNK as usize);
        resp.into_reader()
            .take(CHUNK)
            .read_to_end(&mut bytes)
            .map_err(|e| io::Error::other(format!("读取响应失败: {e}")))?;
        self.cache = bytes;
        self.cache_start = start;
        Ok(())
    }

    /// 保证 `pos` 落在缓存窗口内（不在则重新拉取）。
    fn ensure(&mut self) -> io::Result<()> {
        let hit = !self.cache.is_empty()
            && self.pos >= self.cache_start
            && self.pos < self.cache_start + self.cache.len() as u64;
        if hit {
            return Ok(());
        }
        self.fetch(self.pos)
    }
}

impl Read for HttpMediaSource {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if let Some(len) = self.len {
            if self.pos >= len {
                return Ok(0);
            }
        }
        if buf.is_empty() {
            return Ok(0);
        }
        self.ensure()?;
        if self.cache.is_empty() {
            return Ok(0);
        }
        let offset = (self.pos - self.cache_start) as usize;
        let avail = self.cache.len() - offset;
        let n = avail.min(buf.len());
        buf[..n].copy_from_slice(&self.cache[offset..offset + n]);
        self.pos += n as u64;
        Ok(n)
    }
}

impl Seek for HttpMediaSource {
    fn seek(&mut self, target: SeekFrom) -> io::Result<u64> {
        let new_pos = match target {
            SeekFrom::Start(p) => p as i64,
            SeekFrom::Current(d) => self.pos as i64 + d,
            SeekFrom::End(d) => match self.len {
                Some(len) => len as i64 + d,
                None => return Err(io::Error::other("未知文件长度，无法从尾部 seek")),
            },
        };
        if new_pos < 0 {
            return Err(io::Error::other("seek 位置为负"));
        }
        self.pos = new_pos as u64;
        Ok(self.pos)
    }
}

impl MediaSource for HttpMediaSource {
    fn is_seekable(&self) -> bool {
        true
    }

    fn byte_len(&self) -> Option<u64> {
        self.len
    }
}

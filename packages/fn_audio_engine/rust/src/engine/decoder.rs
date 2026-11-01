//! symphonia 0.6 媒体探测：任意 `MediaSource` → 格式读取器 + 音轨参数。
//!
//! App 的音频来自 HTTP（Range 直出原始文件），因此这里不绑定文件路径：
//! 由调用方把 [`HttpMediaSource`](crate::engine::net::HttpMediaSource) 装成
//! `MediaSourceStream`。探测逻辑与服务端 `audio::decoder::open_media` 一致，
//! 保留源采样率/位深，交给块式解码。

use std::sync::OnceLock;

use symphonia::core::codecs::audio::AudioCodecParameters;
use symphonia::core::codecs::registry::CodecRegistry;
use symphonia::core::codecs::CodecParameters;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, TrackType};
use symphonia::core::io::{MediaSource, MediaSourceStream};
use symphonia::core::meta::MetadataOptions;

/// 音解码器注册表：symphonia 内建全部 + libopus（Opus）。
///
/// symphonia 0.6 没有原生 Opus 解码器，`symphonia::default::get_codecs()`
/// 里也就没有它。这里在首次使用时建一张自己的表，把
/// [`OpusDecoder`](symphonia_adapter_libopus::OpusDecoder) 一起注册进去，
/// 之后 `.ogg`（Opus）与 MP4 里的 Opus 轨都能解。
pub fn codec_registry() -> &'static CodecRegistry {
    static REGISTRY: OnceLock<CodecRegistry> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        let mut registry = CodecRegistry::new();
        symphonia::default::register_enabled_codecs(&mut registry);
        registry.register_audio_decoder::<symphonia_adapter_libopus::OpusDecoder>();
        registry
    })
}

/// 探测后的媒体信息（格式读取器 + 音轨参数），供块式解码使用。
pub struct OpenedMedia {
    pub format: Box<dyn FormatReader>,
    pub track_id: u32,
    pub codec_params: AudioCodecParameters,
    pub sample_rate: u32,
    pub channels: u16,
    pub bits: Option<u32>,
    pub total_frames: Option<u64>,
}

/// 打开媒体流并探测音轨。
///
/// `hint_ext` 是文件扩展名（不含点）：symphonia 对部分容器（如 .m4a / .dff）
/// 靠扩展名才能选对探针。
pub fn open_media(
    source: Box<dyn MediaSource>,
    hint_ext: Option<&str>,
) -> anyhow::Result<OpenedMedia> {
    let mss = MediaSourceStream::new(source, Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = hint_ext {
        hint.with_extension(ext);
    }

    let format = symphonia::default::get_probe().probe(
        &hint,
        mss,
        FormatOptions::default(),
        MetadataOptions::default(),
    )?;

    let track = format
        .default_track(TrackType::Audio)
        .ok_or_else(|| anyhow::anyhow!("文件中没有可解码的音轨"))?;
    let track_id = track.id;
    let total_frames = track.num_frames;
    let codec_params = match track.codec_params.clone() {
        Some(CodecParameters::Audio(p)) => p,
        _ => anyhow::bail!("无法获取音频编码参数"),
    };
    let sample_rate = codec_params
        .sample_rate
        .ok_or_else(|| anyhow::anyhow!("无法获取采样率"))?;
    let channels = codec_params
        .channels
        .clone()
        .map(|c| c.count() as u16)
        .unwrap_or(2);
    // symphonia 0.6：bits_per_sample 是解码位深，bits_per_coded_sample 是编码位深
    // （无损容器两者一致）。无损格式用它判断 Hi-Res 位深。
    let bits = codec_params
        .bits_per_coded_sample
        .or(codec_params.bits_per_sample);

    Ok(OpenedMedia {
        format,
        track_id,
        codec_params,
        sample_rate,
        channels,
        bits,
        total_frames,
    })
}

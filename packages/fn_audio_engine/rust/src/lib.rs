//! App 本地音频引擎（Windows / Android / iOS）。
//!
//! 目标：不依赖平台播放器解复用能力，App 自己完成
//! `原始文件（HTTP Range）→ 解码（symphonia / DSD / Opus）→ 本地 DSP →
//! 重采样 → 输出`，并暴露播放/暂停/seek/进度给 Dart。
//!
//! 与服务端音频模块保持同源（`pcm` / `effects` / `eq` / `crossfeed` / `fade` /
//! `dsp_builtin` / `resampler`），保证同一预设在本机与服务端听感一致。

pub mod api;
pub mod engine;
#[cfg(target_os = "android")]
mod android_jni;

/// 让 Rust panic 在 Android 上也能出现在 logcat（stderr 默认不可见）。
pub fn install_panic_logger() {
    use std::sync::Once;
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            crate::engine::log::warn(&format!("Rust panic: {info}"));
            previous(info);
        }));
    });
}
// FRB 生成的桥接代码（`flutter_rust_bridge_codegen generate` 产物）。
mod frb_generated;

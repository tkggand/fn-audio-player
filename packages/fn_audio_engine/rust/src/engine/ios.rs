//! iOS 音频会话：cpal 的 RemoteIO 后端只配置缓冲区、监听打断与路由变化，
//! 不会主动激活 `AVAudioSession`；会话未激活时音频单元渲染不出声，
//! 需要引擎在创建输出流与恢复播放前显式激活。
//!
//! 类别（`playback`）仍由 Dart 侧 `audio_session` 配置，
//! 后台播放依赖 `Info.plist` 的 `UIBackgroundModes: audio`。

/// 激活（或保持）当前音频会话；对已激活的会话是幂等的。
#[cfg(target_os = "ios")]
pub fn activate_session() {
    use objc2_avf_audio::AVAudioSession;

    // SAFETY: `sharedInstance()` 返回全局音频会话单例，可在任意线程调用。
    unsafe {
        let session = AVAudioSession::sharedInstance();
        if let Err(e) = session.setActive_error(true) {
            crate::engine::log::warn(&format!("激活音频会话失败: {e}"));
        }
    }
}

/// 其他平台无需处理（WASAPI / AAudio 开流即占用设备）。
#[cfg(not(target_os = "ios"))]
pub fn activate_session() {}

use super::AudioManager;

impl AudioManager {
    /// Get the AAudio mixer burst count from system property
    pub fn get_mixer_bursts() -> Result<i32, String> {
        // FN-Audio patch：不查询 `aaudio.mixer_bursts`。
        //
        // 该路径要求 `ndk_context` 里保存的 JavaVM 指针同时满足两套互相冲突的约定：
        // jni 0.22 期望「指向 JNIInvokeInterface 表指针的槽」，而 ART 的
        // `JNIInvokeInterface::GetEnv` 直接把入参当 `_JavaVM*` 解引用（实测会在
        // `call *0x30(%rax)` 处 SIGSEGV）。
        //
        // 返回 Err 后 cpal 走 `stream.frames_per_burst()` 回退，效果相同且不碰 JNI。
        Err("FN-Audio: 跳过 JNI 的 mixer_bursts 查询".to_string())
    }
}

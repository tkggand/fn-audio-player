//! Android 运行时初始化：把 JavaVM / Context 交给 `ndk_context`。
//!
//! Kotlin 侧 `MainActivity` 在 `onCreate` 调用本模块导出的 native 方法，
//! 供后续任何需要 JNI 的系统查询（如设备信息）使用。当前音频输出路径
//! 不依赖它——cpal 的 `aaudio.mixer_bursts` 查询已在 `third_party/cpal`
//! 里短路（原因见 `Cargo.toml` 的 `[patch.crates-io]` 注释）。

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};

static INITIALIZED: AtomicBool = AtomicBool::new(false);

/// 由 Kotlin `MainActivity.initAudioContext(applicationContext)` 调用。
///
/// 符号里的 `fn_1audio` 是 JNI 对包名中下划线的转义（`fn_audio` → `fn_1audio`），
/// 不能直接写成包名原样。
///
/// 需要对 Context 建全局引用：本地引用只在本次 JNI 调用内有效，后续线程
/// 可能长期使用它。
///
/// # Safety
/// 只能由 JVM 调用，`env` / `context` 必须是对应 JNI 调用的合法指针。
#[no_mangle]
pub unsafe extern "system" fn Java_com_fnaudio_fn_1audio_MainActivity_initAudioContext(
    env: *mut jni_sys::JNIEnv,
    _this: jni_sys::jobject,
    context: jni_sys::jobject,
) {
    if env.is_null() || context.is_null() {
        return;
    }
    if INITIALIZED.load(Ordering::SeqCst) {
        return;
    }
    let functions = *env;
    if functions.is_null() {
        return;
    }
    let Some(get_java_vm) = (*functions).GetJavaVM else {
        crate::engine::log::warn("JNI 缺少 GetJavaVM");
        return;
    };
    // jni-sys 把 JavaVM 建模成指针类型，字段签名因此多了一层（C 的 JavaVM**）。
    let mut vm_slot: *mut jni_sys::JavaVM = std::ptr::null_mut();
    if get_java_vm(env, &mut vm_slot) != jni_sys::JNI_OK || vm_slot.is_null() {
        crate::engine::log::warn("GetJavaVM 失败");
        return;
    }
    let vm = *vm_slot;
    if vm.is_null() {
        crate::engine::log::warn("GetJavaVM 返回空指针");
        return;
    }
    let Some(new_global_ref) = (*functions).NewGlobalRef else {
        crate::engine::log::warn("JNI 缺少 NewGlobalRef");
        return;
    };
    let global = new_global_ref(env, context);
    if global.is_null() {
        crate::engine::log::warn("NewGlobalRef 失败");
        return;
    }
    // `ndk_context` 存 JNI 的 `JavaVM` 值（ART 的 JNIInvokeInterface 表指针）。
    ndk_context::initialize_android_context(vm as *mut c_void, global as *mut c_void);
    INITIALIZED.store(true, Ordering::SeqCst);
    crate::engine::log::info(&format!("Android JNI 上下文已注册 vm={vm:p} ctx={global:p}"));
}

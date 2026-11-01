//! 引擎日志：Android 写 logcat（tag `fn-audio-engine`），其它平台写 stderr。
//!
//! Android 上 Rust 的 stderr 不会出现在 logcat，排查音频线程问题必须走这里。

pub fn info(msg: &str) {
    write(4 /* ANDROID_LOG_INFO */, msg);
}

pub fn warn(msg: &str) {
    write(5 /* ANDROID_LOG_WARN */, msg);
}

fn write(prio: i32, msg: &str) {
    #[cfg(target_os = "android")]
    unsafe {
        use std::ffi::CString;
        use std::os::raw::c_char;

        #[link(name = "log")]
        extern "C" {
            fn __android_log_write(prio: i32, tag: *const c_char, text: *const c_char) -> i32;
        }

        if let Ok(text) = CString::new(msg) {
            let tag = b"fn-audio-engine\0".as_ptr() as *const c_char;
            __android_log_write(prio, tag, text.as_ptr());
        }
    }
    #[cfg(not(target_os = "android"))]
    {
        let _ = prio;
        eprintln!("[fn-audio-engine] {msg}");
    }
}

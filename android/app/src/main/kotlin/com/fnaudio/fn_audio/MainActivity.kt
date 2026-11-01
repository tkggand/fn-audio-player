package com.fnaudio.fn_audio

import android.content.Context
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

// audio_service 要求宿主 Activity 继承 AudioServiceActivity（其本身是 FlutterActivity），
// 否则后台播放服务与通知栏/锁屏控制无法挂载。
//
// 另外，本地音频引擎（Rust）的 cpal AAudio 后端需要 JavaVM + Context，
// 启动时通过 JNI 交给 ndk_context（见 rust/src/android_jni.rs）。
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initAudioContext(applicationContext)
    }

    private external fun initAudioContext(context: Context)

    companion object {
        init {
            System.loadLibrary("fn_audio_engine")
        }
    }
}

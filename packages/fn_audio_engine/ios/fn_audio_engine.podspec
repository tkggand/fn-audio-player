Pod::Spec.new do |s|
  s.name             = 'fn_audio_engine'
  s.version          = '0.1.0'
  s.summary          = 'FN Audio local audio engine (Rust).'
  s.description      = <<-DESC
FN Audio 本地音频引擎：全格式解码 + 本地 DSP。
                       DESC
  s.homepage         = 'https://example.com'
  s.author           = { 'FN Audio' => 'dev@fnaudio.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # 与 App 的 IPHONEOS_DEPLOYMENT_TARGET 保持一致。
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'

  # Rust 静态库不会把 objc2 的 `#[link(kind = "framework")]` 带到最终链接阶段，
  # cpal 的 RemoteIO 后端依赖的这些系统框架必须在 pod 里显式声明，
  # 否则编译 pod framework 时会出现大量 undefined symbol（AVAudioSession / AudioUnit 等）。
  s.frameworks = 'AVFAudio', 'AudioToolbox', 'CoreAudio', 'CoreFoundation', 'Foundation'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libfn_audio_engine.a -framework AVFAudio -framework AudioToolbox -framework CoreAudio -framework CoreFoundation -framework Foundation',
  }

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust fn_audio_engine',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libfn_audio_engine.a"],
  }
end

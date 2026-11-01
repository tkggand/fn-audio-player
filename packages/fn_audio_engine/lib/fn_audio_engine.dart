/// FN Audio 本地音频引擎（Rust）：全格式解码 + 本地 DSP。
///
/// 使用前先 `await RustLib.init()`，再 `engineInit` 等待输出设备就绪；
/// 之后 `engineLoad` / `enginePlay` / `engineStatus` 即可驱动播放。
library;

export 'src/rust/api.dart';
export 'src/rust/engine/player.dart' show EngineStatus;
export 'src/rust/frb_generated.dart' show RustLib;

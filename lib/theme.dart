/// FN Audio 主题入口。
///
/// - `theme/fn_palette.dart`：语义调色板 + 静态令牌入口 [FnColors]
/// - `theme/fn_theme_data.dart`：浅/深两套独立 ThemeData（[FnThemes]）与文字样式
/// - `theme/fn_theme_controller.dart`：主题模式持久化
///
/// 页面统一从这里 import，避免直接依赖内部文件。
library;

export 'theme/fn_palette.dart';
export 'theme/fn_theme_controller.dart';
export 'theme/fn_theme_data.dart';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 语言模式：跟随系统 / 简体中文 / English。
enum FnLocaleMode { system, zh, en }

extension FnLocaleModeX on FnLocaleMode {
  /// null 表示交给 Flutter 按系统语言在 supportedLocales 中匹配。
  Locale? get locale => switch (this) {
        FnLocaleMode.system => null,
        FnLocaleMode.zh => const Locale('zh'),
        FnLocaleMode.en => const Locale('en'),
      };

  String get storageValue => name;
}

/// 语言选择持久化。与主题控制器同构：启动前读取，切换时重建 MaterialApp。
class FnLocaleController extends ValueNotifier<FnLocaleMode> {
  FnLocaleController._() : super(FnLocaleMode.system);

  static final FnLocaleController instance = FnLocaleController._();

  static const _key = 'fn_audio_locale';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) {
        value = FnLocaleMode.values.firstWhere(
          (m) => m.storageValue == saved,
          orElse: () => FnLocaleMode.system,
        );
      }
    } catch (_) {
      // 读取失败按跟随系统处理，不阻塞启动。
    }
  }

  Future<void> setMode(FnLocaleMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.storageValue);
    } catch (_) {
      // 写入失败只影响下次启动，不阻塞本次切换。
    }
  }
}

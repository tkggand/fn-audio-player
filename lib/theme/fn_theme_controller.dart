import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart' show Brightness, State, StatefulWidget;
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式：深色 / 浅色 / 跟随系统。
enum FnThemeMode { dark, light, auto }

extension FnThemeModeX on FnThemeMode {
  bool get isDark => this == FnThemeMode.dark;

  bool get isAuto => this == FnThemeMode.auto;

  /// auto 取当前系统亮度（Android / Windows 跟随系统外观）。
  Brightness get brightness => switch (this) {
        FnThemeMode.dark => Brightness.dark,
        FnThemeMode.light => Brightness.light,
        FnThemeMode.auto =>
          PlatformDispatcher.instance.platformBrightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
      };

  String get storageValue => name;
}

/// 主题控制器：全局单例 + [ValueNotifier]，根节点监听它重建整棵树。
///
/// 之所以不用 Riverpod：主题需要在 App 启动前就确定（避免首帧闪白），
/// 且切换时要重建 MaterialApp，ValueNotifier 最直接。
class FnThemeController extends ValueNotifier<FnThemeMode> {
  FnThemeController._() : super(FnThemeMode.dark);

  static final FnThemeController instance = FnThemeController._();

  static const _key = 'fn_audio_theme_mode';

  /// 读取本地持久化的选择，在 runApp 之前调用（失败时保持深色）。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) {
        value = FnThemeMode.values.firstWhere(
          (m) => m.storageValue == saved,
          orElse: () => FnThemeMode.dark,
        );
      }
    } catch (_) {
      // 读取失败按深色处理，不阻塞启动。
    }
  }

  Future<void> setMode(FnThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.storageValue);
    } catch (_) {
      // 写入失败不影响本次切换，仅下次启动不保留。
    }
  }

  Future<void> toggle() => setMode(
        value.isDark ? FnThemeMode.light : FnThemeMode.dark,
      );
}

/// 让常驻页面跟随主题切换重绘。
///
/// 配色令牌 [FnColors] 是静态表，页面并不构成 InheritedWidget 依赖；
/// 而底部 4 个 Tab 页常驻在 StatefulShellRoute 的 IndexedStack 里，
/// 切换主题时只会重建外壳，分支页面保持旧配色。常驻页混入它即可自更新。
mixin FnThemeAware<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    FnThemeController.instance.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FnThemeController.instance.removeListener(_onThemeChanged);
    super.dispose();
  }
}

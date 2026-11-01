
import 'package:flutter/cupertino.dart'
    show CupertinoTextThemeData, CupertinoThemeData;
import 'package:flutter/material.dart';

import 'fn_palette.dart';

/// 圆角令牌（v2：6 / 12 / 20 / 28 / 36 / pill）。
class FnRadius {
  FnRadius._();
  static const double xs = 6;
  static const double sm = 12;
  static const double md = 20;
  static const double lg = 28;
  static const double xl = 36;
  static const double pill = 999;

  static const Radius group = Radius.circular(sm);
  static const Radius card = Radius.circular(md);
  static const BorderRadius groupAll = BorderRadius.all(group);
  static const BorderRadius cardAll = BorderRadius.all(card);
}

/// 字体：SF Pro / PingFang（各平台回退到系统中文字体）。
class FnText {
  FnText._();
  static const List<String> fontFamily = [
    'SF Pro Display',
    'SF Pro Text',
    '-apple-system',
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'sans-serif',
  ];
  static const List<String> monoFamily = [
    'SF Mono',
    'Cascadia Mono',
    'Consolas',
    'monospace',
  ];
}

/// 常用文字样式：v2 字号阶梯。
class FnTextStyles {
  FnTextStyles._(this._p);

  final FnPalette _p;

  static FnTextStyles of(BuildContext context) => FnTextStyles._(
      Theme.of(context).extension<FnPalette>() ?? FnColors.palette);

  TextStyle get h1 => TextStyle(
        fontSize: 32,
        height: 1.06,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: _p.textPrimary,
      );

  TextStyle get h2 => TextStyle(
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: _p.textPrimary,
      );

  TextStyle get h3 => TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.16,
        color: _p.textPrimary,
      );

  TextStyle get eyebrow => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.68,
        color: _p.textTertiary,
      );

  TextStyle get meta => TextStyle(fontSize: 12, color: _p.textSecondary);

  TextStyle get mono => TextStyle(
        fontSize: 11,
        fontFamily: FnText.monoFamily.first,
        fontFamilyFallback: FnText.monoFamily.sublist(1),
        fontFeatures: const [FontFeature.tabularFigures()],
        color: _p.textTertiary,
      );

  // 旧命名别名。
  TextStyle get pageTitle => h1;
  TextStyle get navTitle => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.16,
        color: _p.textPrimary,
      );
  TextStyle get sectionTitle => h2;
  TextStyle get rowTitle =>
      TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: _p.textPrimary);
  TextStyle get rowValue => TextStyle(fontSize: 12.5, color: _p.textSecondary);
  TextStyle get groupLabel => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.47,
        color: _p.textTertiary,
      );
  TextStyle get caption => TextStyle(fontSize: 11.5, color: _p.textTertiary);
}

TextTheme _textTheme(FnPalette p) {
  return TextTheme(
    displayLarge: TextStyle(
        fontSize: 32,
        height: 1.06,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
        color: p.textPrimary),
    titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: p.textPrimary),
    titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.16,
        color: p.textPrimary),
    bodyLarge: TextStyle(fontSize: 15, color: p.textPrimary),
    bodyMedium: TextStyle(fontSize: 14, color: p.textPrimary),
    bodySmall: TextStyle(fontSize: 12, color: p.textSecondary),
    labelSmall: TextStyle(fontSize: 10.5, color: p.textTertiary),
  );
}

CupertinoThemeData buildFnCupertinoTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? fnDarkPalette : fnLightPalette;
  final base = TextStyle(
    fontFamily: FnText.fontFamily.first,
    fontFamilyFallback: FnText.fontFamily.sublist(1),
    color: p.textPrimary,
    fontSize: 16,
    letterSpacing: -0.2,
  );
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: p.lime,
    scaffoldBackgroundColor: p.base,
    barBackgroundColor: p.glass,
    textTheme: CupertinoTextThemeData(
      textStyle: base,
      navTitleTextStyle:
          base.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
      navLargeTitleTextStyle: base.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.1,
      ),
    ),
  );
}

ThemeData _buildTheme(FnPalette p) {
  final dark = p.isDark;
  final brightness = dark ? Brightness.dark : Brightness.light;

  final scheme = dark
      ? ColorScheme.dark(
          primary: p.lime,
          onPrimary: p.limeInk,
          secondary: p.coral,
          surface: p.surface,
          onSurface: p.textPrimary,
          error: p.coral,
        )
      : ColorScheme.light(
          primary: p.lime,
          onPrimary: p.limeInk,
          secondary: p.coral,
          surface: p.surface,
          onSurface: p.textPrimary,
          error: p.coral,
        );

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.base,
    canvasColor: p.base,
    dividerColor: p.line,
    fontFamily: FnText.fontFamily.first,
    fontFamilyFallback: FnText.fontFamily.sublist(1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [p],
  );

  return base.copyWith(
    cupertinoOverrideTheme: buildFnCupertinoTheme(brightness),
    textTheme: _textTheme(p),
    appBarTheme: AppBarTheme(
      backgroundColor: p.base,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: p.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.16,
      ),
      iconTheme: IconThemeData(color: p.textPrimary, size: 20),
      actionsIconTheme: IconThemeData(color: p.textPrimary, size: 20),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: p.textSecondary,
      textColor: p.textPrimary,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.lime,
      inactiveTrackColor: p.surface3,
      thumbColor: Colors.white,
      overlayColor: p.lime.withValues(alpha: 0.16),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.limeInk : Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.lime : p.surface3),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface2,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: p.lime, width: 1.2),
      ),
      labelStyle: TextStyle(color: p.textSecondary),
      hintStyle: TextStyle(color: p.textTertiary),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.lime),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface2,
      contentTextStyle: TextStyle(color: p.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.lime,
      linearTrackColor: p.surface3,
    ),
  );
}

class FnThemes {
  FnThemes._();
  static final ThemeData light = _buildTheme(fnLightPalette);
  static final ThemeData dark = _buildTheme(fnDarkPalette);
}

ThemeData buildFnTheme(Brightness brightness) =>
    brightness == Brightness.dark ? FnThemes.dark : FnThemes.light;

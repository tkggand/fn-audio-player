import 'package:flutter/material.dart';

/// FN Audio v2 · 调色板
///
/// 墨黑底 × 青柠主色 × 珊瑚收藏色 × 封面氛围渐变。
/// 深/浅两套共享同一组语义令牌，页面通过 [FnColors] 或
/// `Theme.of(context).extension<FnPalette>()` 读取。
class FnPalette extends ThemeExtension<FnPalette> {
  const FnPalette({
    required this.base,
    required this.base2,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.glass,
    required this.glass2,
    required this.glassLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textFaint,
    required this.line,
    required this.line2,
    required this.lime,
    required this.limeSoft,
    required this.limeInk,
    required this.coral,
    required this.coralSoft,
    required this.gold,
    required this.cyan,
    required this.violet,
    required this.green,
    required this.blue,
    required this.coverVeil,
    required this.isDark,
  });

  /// 页面底色。
  final Color base;

  /// 稍浅的页面底色（沉浸页渐变终点）。
  final Color base2;

  /// 卡片 / 分组容器。
  final Color surface;

  /// 输入框 / 次级容器。
  final Color surface2;

  /// 轨道 / 更深的抬升面。
  final Color surface3;

  /// 毛玻璃填充（导航、迷你播放器）。
  final Color glass;

  /// 更不透明的毛玻璃（迷你播放器 / 浮层）。
  final Color glass2;

  /// 极轻叠层（圆形按钮底、chip 底）。
  final Color glassLight;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textFaint;

  /// 发丝分隔线。
  final Color line;

  /// 更明显的描边。
  final Color line2;

  /// 主色：青柠。
  final Color lime;
  final Color limeSoft;
  final Color limeInk;

  /// 收藏 / 警示：珊瑚。
  final Color coral;
  final Color coralSoft;

  final Color gold;
  final Color cyan;
  final Color violet;
  final Color green;
  final Color blue;

  /// 封面叠色。
  final Color coverVeil;

  final bool isDark;

  // ---- 旧令牌别名（共享弹层仍在用） ----
  Color get raised => surface;
  Color get raisedHigh => surface2;
  Color get material => glass;
  Color get divider => line;
  Color get trackFill => surface3;
  Color get overlay => glassLight;
  Color get overlayWeak => glassLight;
  Color get border => line2;
  Color get tabBar => glass;
  Color get scrimSoft => isDark ? const Color(0x0A000000) : const Color(0x00FFFFFF);
  Color get scrimFaint =>
      isDark ? const Color(0x1F000000) : const Color(0x0DFFFFFF);
  Color get scrimMid =>
      isDark ? const Color(0x66000000) : const Color(0x40FFFFFF);
  Color get scrimStrong =>
      isDark ? const Color(0xDB000000) : const Color(0xD9FFFFFF);
  Color get barrier => isDark ? const Color(0x94000000) : const Color(0x33000000);
  Color get glassFill => glass2;
  Color get glassShadow => isDark ? const Color(0xE0000000) : const Color(0x1F000000);

  @override
  FnPalette copyWith({
    Color? base,
    Color? base2,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? glass,
    Color? glass2,
    Color? glassLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textFaint,
    Color? line,
    Color? line2,
    Color? lime,
    Color? limeSoft,
    Color? limeInk,
    Color? coral,
    Color? coralSoft,
    Color? gold,
    Color? cyan,
    Color? violet,
    Color? green,
    Color? blue,
    Color? coverVeil,
    bool? isDark,
  }) {
    return FnPalette(
      base: base ?? this.base,
      base2: base2 ?? this.base2,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      glass: glass ?? this.glass,
      glass2: glass2 ?? this.glass2,
      glassLight: glassLight ?? this.glassLight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textFaint: textFaint ?? this.textFaint,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      lime: lime ?? this.lime,
      limeSoft: limeSoft ?? this.limeSoft,
      limeInk: limeInk ?? this.limeInk,
      coral: coral ?? this.coral,
      coralSoft: coralSoft ?? this.coralSoft,
      gold: gold ?? this.gold,
      cyan: cyan ?? this.cyan,
      violet: violet ?? this.violet,
      green: green ?? this.green,
      blue: blue ?? this.blue,
      coverVeil: coverVeil ?? this.coverVeil,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  FnPalette lerp(ThemeExtension<FnPalette>? other, double t) {
    if (other is! FnPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return FnPalette(
      base: mix(base, other.base),
      base2: mix(base2, other.base2),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      surface3: mix(surface3, other.surface3),
      glass: mix(glass, other.glass),
      glass2: mix(glass2, other.glass2),
      glassLight: mix(glassLight, other.glassLight),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textFaint: mix(textFaint, other.textFaint),
      line: mix(line, other.line),
      line2: mix(line2, other.line2),
      lime: mix(lime, other.lime),
      limeSoft: mix(limeSoft, other.limeSoft),
      limeInk: mix(limeInk, other.limeInk),
      coral: mix(coral, other.coral),
      coralSoft: mix(coralSoft, other.coralSoft),
      gold: mix(gold, other.gold),
      cyan: mix(cyan, other.cyan),
      violet: mix(violet, other.violet),
      green: mix(green, other.green),
      blue: mix(blue, other.blue),
      coverVeil: mix(coverVeil, other.coverVeil),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// 深色：墨黑 + 青柠。
const FnPalette fnDarkPalette = FnPalette(
  base: Color(0xFF07080A),
  base2: Color(0xFF0B0D10),
  surface: Color(0xFF121418),
  surface2: Color(0xFF191C21),
  surface3: Color(0xFF23272E),
  glass: Color(0xB8121418), // rgba(18,20,24,.72)
  glass2: Color(0xE6121418), // rgba(18,20,24,.90)
  glassLight: Color(0x0FFFFFFF), // rgba(255,255,255,.06)
  textPrimary: Color(0xFFF5F7FA),
  textSecondary: Color(0x9EF5F7FA), // .62
  textTertiary: Color(0x5CF5F7FA), // .36
  textFaint: Color(0x2EF5F7FA), // .18
  line: Color(0x14FFFFFF), // .08
  line2: Color(0x24FFFFFF), // .14
  lime: Color(0xFFCDFF4A),
  limeSoft: Color(0x24CDFF4A), // .14
  limeInk: Color(0xFF101400),
  coral: Color(0xFFFF5A6A),
  coralSoft: Color(0x24FF5A6A),
  gold: Color(0xFFFFC24B),
  cyan: Color(0xFF5EE7FF),
  violet: Color(0xFFB48CFF),
  green: Color(0xFF3DDC84),
  blue: Color(0xFF5A8CFF),
  coverVeil: Color(0x3307080A),
  isDark: true,
);

/// 浅色：暖白 + 青柠。
const FnPalette fnLightPalette = FnPalette(
  base: Color(0xFFF1F2EC),
  base2: Color(0xFFE9EAE2),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFF6F7F1),
  surface3: Color(0xFFECEEE5),
  glass: Color(0xBCFFFFFF), // rgba(255,255,255,.74)
  glass2: Color(0xEBFFFFFF), // rgba(255,255,255,.92)
  glassLight: Color(0x0D101208), // rgba(16,18,8,.05)
  textPrimary: Color(0xFF11130B),
  textSecondary: Color(0x9E11130B), // .62
  textTertiary: Color(0x6111130B), // .38
  textFaint: Color(0x2E11130B), // .18
  line: Color(0x1411130B),
  line2: Color(0x2411130B),
  lime: Color(0xFFA8DD00),
  limeSoft: Color(0x29A8DD00), // .16
  limeInk: Color(0xFF141800),
  coral: Color(0xFFE63B50),
  coralSoft: Color(0x1FE63B50),
  gold: Color(0xFFA06D00),
  cyan: Color(0xFF008FAE),
  violet: Color(0xFF7A4DDB),
  green: Color(0xFF12A05A),
  blue: Color(0xFF2F64D8),
  coverVeil: Color(0x29F1F2EC),
  isDark: false,
);

/// 歌词已唱部分的三色渐变配置（左 → 右：起 → 中 → 终）。
///
/// 直接改这里的三个颜色即可调整扫色效果，深浅主题各一套。
const List<Color> fnLyricSweepDark = [
  Color(0xFFFFC24B), // 金
  Color(0xFFCDFF4A), // 青柠
  Color(0xFF3DDC84), // 绿
];

const List<Color> fnLyricSweepLight = [
  Color(0xFFA06D00), // 深金
  Color(0xFF4F6B00), // 深橄榄
  Color(0xFF0E8A4F), // 深绿
];

/// 从 Theme 取当前调色板。
FnPalette fnPaletteOf(BuildContext context) =>
    Theme.of(context).extension<FnPalette>() ?? FnColors.palette;

/// 语义色静态入口（保留给尚未迁移到 Theme 的共享组件）。
class FnColors {
  FnColors._();

  static Brightness _brightness = Brightness.dark;

  /// 切换当前生效的调色板，需在整棵树 build 之前调用。
  static void applyBrightness(Brightness value) => _brightness = value;

  static FnPalette get palette =>
      _brightness == Brightness.dark ? fnDarkPalette : fnLightPalette;

  static bool get isDark => _brightness == Brightness.dark;

  static Color get base => palette.base;
  static Color get base2 => palette.base2;
  static Color get surface => palette.surface;
  static Color get surface2 => palette.surface2;
  static Color get surface3 => palette.surface3;
  static Color get raised => palette.surface;
  static Color get raisedHigh => palette.surface2;
  static Color get material => palette.glass;
  static Color get glass => palette.glass;
  static Color get glass2 => palette.glass2;
  static Color get glassLight => palette.glassLight;
  static Color get divider => palette.line;
  static Color get line => palette.line;
  static Color get line2 => palette.line2;
  static Color get textPrimary => palette.textPrimary;
  static Color get textSecondary => palette.textSecondary;
  static Color get textTertiary => palette.textTertiary;
  static Color get textFaint => palette.textFaint;
  static Color get trackFill => palette.surface3;
  static Color get overlayFill => palette.glassLight;
  static Color get overlayWeak => palette.glassLight;
  static Color get overlayBorder => palette.line2;
  static Color get border => palette.line2;
  static Color get tabBar => palette.glass;
  static Color get scrimSoft => palette.scrimSoft;
  static Color get scrimFaint => palette.scrimFaint;
  static Color get scrimMid => palette.scrimMid;
  static Color get scrimStrong => palette.scrimStrong;
  static Color get barrier => palette.barrier;
  static Color get glassFill => palette.glass2;
  static Color get glassShadow => palette.glassShadow;
  static Color get coverVeil => palette.coverVeil;

  /// 主色：青柠。随主题取当前调色板（浅色为 #A8DD00，深色为 #CDFF4A），
  /// 因此不能在 const 上下文中使用。
  static Color get primary => palette.lime;
  static Color get primaryAlt => palette.lime;
  static Color get onPrimary => palette.limeInk;

  /// 歌词扫色层的三色渐变（配置见 [fnLyricSweepDark] / [fnLyricSweepLight]）。
  static List<Color> get lyricSweep =>
      isDark ? fnLyricSweepDark : fnLyricSweepLight;

  static Color get lime => palette.lime;

  /// 浅色底上的强调色文字与图标：深色主题等于 [lime]，浅色主题用加深的橄榄绿，
  /// 保证小号文字对比度（青柠 #A8DD00 在米白底上仅约 1.9:1）。
  static Color get limeText =>
      isDark ? palette.lime : const Color(0xFF4F6B00);
  static Color get limeSoft => palette.limeSoft;
  static Color get limeInk => palette.limeInk;
  static Color get coral => palette.coral;
  static Color get coralSoft => palette.coralSoft;
  static Color get gold => palette.gold;
  static Color get cyan => palette.cyan;
  static Color get violet => palette.violet;
  static Color get green => palette.green;
  static Color get blue => palette.blue;

  static Color get orange => palette.gold;
  static Color get purple => palette.violet;
  static Color get red => palette.coral;
}

import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// 毛玻璃材质：背景模糊 + 半透明填充 + 发丝描边。
///
/// 用于悬浮在内容之上的播放控制、迷你播放条与音量浮层；圆角与描边统一
/// 由 [radius] / [border] 控制，避免各处硬编码模糊参数。
class FnGlass extends StatelessWidget {
  const FnGlass({
    super.key,
    required this.child,
    this.radius = 0,
    this.blur = 24,
    this.color,
    this.border,
    this.padding,
    this.shadow,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color? color;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final content =
        padding == null ? child : Padding(padding: padding!, child: child);
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color ?? FnColors.material,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: content,
        ),
      ),
    );
    if (shadow == null) return clipped;
    // 投影必须画在裁剪层之外，否则会被 ClipRRect 一并裁掉。
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: clipped,
    );
  }
}

/// iOS 列表行尾细箭头（与 CupertinoListTile 一致），替换 Material 的粗箭头。
class FnChevron extends StatelessWidget {
  const FnChevron({super.key, this.size = 17});
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
        CupertinoIcons.chevron_forward,
        size: size,
        color: FnColors.textTertiary,
      );
}

/// 封面图：网络加载 + 统一的占位样式。
class FnCover extends StatelessWidget {
  const FnCover({
    super.key,
    required this.songId,
    this.size = 44,
    this.radius = 6,
    this.kind,
  });

  final int songId;
  final double size;
  final double radius;

  /// 封面类型：null = 歌曲；`album` = 按专辑 id 取其首曲封面。
  final String? kind;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          ApiClient.instance.coverUrl(songId, kind: kind),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: FnColors.raisedHigh,
            child: Icon(CupertinoIcons.music_note,
                size: size.isFinite ? size * 0.45 : 22,
                color: FnColors.textTertiary),
          ),
        ),
      ),
    );
  }
}

/// 品牌标：红色渐变圆角方块 + 白色音波符号。
///
/// 与 design/style.css 的 `.side-brand .mark` 同源（尺寸/圆角/渐变按比例换算），
/// 音波符号直接复用 design/app.html 的 `#i-dsp` 路径，与 Windows 应用图标一致。
class FnBrandMark extends StatelessWidget {
  const FnBrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.25),
        gradient: LinearGradient(
          begin: const Alignment(-0.34, -0.94),
          end: const Alignment(0.34, 0.94),
          colors: [FnColors.primaryAlt, FnColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: FnColors.primary.withValues(alpha: 0.35),
            blurRadius: size * 0.43,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: CustomPaint(painter: _BrandGlyphPainter()),
    );
  }
}

/// 音波符号：`M3 12h2.2l2-6 3 13 3-15 2.6 12 1.8-4H21`（24×24 viewBox）。
class _BrandGlyphPainter extends CustomPainter {
  static const _pts = <Offset>[
    Offset(3, 12),
    Offset(5.2, 12),
    Offset(7.2, 6),
    Offset(10.2, 19),
    Offset(13.2, 4),
    Offset(15.8, 16),
    Offset(17.6, 12),
    Offset(21, 12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // 等比缩放到 viewBox，符号宽度占图标 56%，bbox 居中。
    final k = size.width * 0.56 / 18;
    final cx = size.width / 2;
    final cy = size.height / 2;
    const bx = 12.0, by = 11.5;
    final paint = Paint()
      ..color = FnColors.onPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * k
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final dx = cx + (_pts[i].dx - bx) * k;
      final dy = cy + (_pts[i].dy - by) * k;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BrandGlyphPainter oldDelegate) => false;
}

/// 分组列表容器（Apple inset group）：抬升面 + 圆角，行之间靠分隔线。
class InsetGroup extends StatelessWidget {
  const InsetGroup(
      {super.key, required this.children, this.header, this.padding});

  final List<Widget> children;
  final Widget? header;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: DefaultTextStyle(
              style: TextStyle(
                fontSize: 12,
                color: FnColors.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
              child: header!,
            ),
          ),
        Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: FnColors.raised,
              borderRadius: FnRadius.groupAll,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

/// 分组列表内的一行：图标 + 标题 + 副标题 + 尾部，用分隔线区隔。
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        // iOS 列表行最小高度 44pt。
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 9 : 11),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 15 : 16,
                        color: FnColors.textPrimary,
                        // iOS 列表行标题为常规字重，选中态才加粗。
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: FnColors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 行间分隔线（左侧留白，Apple 观感）。
class GroupDivider extends StatelessWidget {
  const GroupDivider({super.key, this.indent = 14, this.color});
  final double indent;
  final Color? color;
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        color: color ?? FnColors.divider,
      );
}

/// 时长格式化 mm:ss。
String fmtDuration(double? sec) {
  if (sec == null || sec.isNaN || sec < 0) return '--:--';
  final m = sec ~/ 60;
  final s = (sec % 60).floor();
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 采样率格式化（如 44.1k）。
String fmtSampleRate(int? sr) {
  if (sr == null || sr <= 0) return '-';
  final k = sr / 1000.0;
  return '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
}

/// 页面大标题栏：白色圆形音符标 + 30px 标题 + 右侧圆形按钮组。
///
/// 首页 / 片段 / 曲库三个 Tab 共用（对齐 design/app.html 的 `.phead`）。
class FnPageHead extends StatelessWidget {
  const FnPageHead({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FnColors.textPrimary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.music_note,
              size: 22,
              color: FnColors.base,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.75,
                color: FnColors.textPrimary,
              ),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 页头圆形按钮：38×38、半透明底 + 发丝描边、20px 图标。
class FnHeaderButton extends StatelessWidget {
  const FnHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.avatar,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// 传入头像图片地址时铺满圆形（曲库右上角「我的」入口）。
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: avatar == null ? FnColors.overlayWeak : null,
          shape: BoxShape.circle,
          border: Border.all(color: FnColors.overlayBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: avatar == null
            ? Icon(icon, size: 20, color: FnColors.textPrimary)
            : Image.network(
                avatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(icon, size: 20, color: FnColors.textPrimary),
              ),
      ),
    );
  }
}

/// 区块标题：19.5px 粗体，右侧可选文字胶囊。
class FnSectionHead extends StatelessWidget {
  const FnSectionHead({
    super.key,
    required this.title,
    this.pillText,
    this.onPillTap,
  });

  final String title;
  final String? pillText;
  final VoidCallback? onPillTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 19.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: FnColors.textPrimary,
              ),
            ),
          ),
          if (pillText != null)
            GestureDetector(
              onTap: onPillTap,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: FnColors.overlayBorder),
                ),
                alignment: Alignment.center,
                child: Text(
                  pillText!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FnColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 横滑封面卡：158 封面 + 标题 + 副标题（对齐 `.art`）。
class FnRailArt extends StatelessWidget {
  const FnRailArt({
    super.key,
    required this.song,
    required this.onTap,
    this.width = 158,
    this.sub,
    this.badge,
  });

  final Song song;
  final VoidCallback onTap;
  final double width;
  final String? sub;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                FnCover(songId: song.id, size: width, radius: 8),
                if (badge != null)
                  Positioned(right: 7, bottom: 7, child: badge!),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: FnColors.textPrimary,
              ),
            ),
            Text(
              sub ?? song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: FnColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌曲行：封面 46 + 标题/艺人 + 时长，当前曲目用主色高亮（`.song`）。
class FnSongRow extends StatelessWidget {
  const FnSongRow({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.isCurrent = false,
    this.ord,
    this.trailing,
    this.showDuration = true,
    this.showArtist = true,
    this.subtitle,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isCurrent;
  final String? ord;
  final Widget? trailing;
  final bool showDuration;
  final bool showArtist;

  /// 覆盖默认的艺人行（艺人 / 专辑 / 风格页展示年份、专辑、风格）。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            if (ord != null) ...[
              SizedBox(
                width: 18,
                child: Text(
                  ord!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent ? FnColors.primary : FnColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            FnCover(songId: song.id, size: 46, radius: 5),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color:
                          isCurrent ? FnColors.primary : FnColors.textPrimary,
                    ),
                  ),
                  if (showArtist) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle ?? song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: FnColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showDuration) ...[
              const SizedBox(width: 8),
              Text(
                fmtDuration(song.duration),
                style: TextStyle(
                  fontSize: 11.5,
                  color: FnColors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组标题（设置页 / 我的页的「音频」「播放与曲库」「系统」）。
class FnGroupLabel extends StatelessWidget {
  const FnGroupLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(32, 0, 32, 7),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(text, style: FnTextStyles.of(context).groupLabel),
    );
  }
}

/// 设置分组卡：抬升面 + 圆角，行之间自动插入分隔线。
class FnSectionCard extends StatelessWidget {
  const FnSectionCard({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
    this.radius = 14,
    this.color,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: color ?? p.raised,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) GroupDivider(color: p.divider),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置行：左图标 + 标题 + 右侧值 / 箭头。整行可点，高度固定 49。
class FnSettingRow extends StatelessWidget {
  const FnSettingRow({
    super.key,
    required this.label,
    this.icon,
    this.value,
    this.onTap,
    this.color,
    this.showChevron = true,
    this.height = 49,
  });

  final String label;
  final IconData? icon;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;
  final bool showChevron;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    final rowColor = color ?? p.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: color ?? p.textSecondary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, color: rowColor),
                ),
              ),
              if (value != null)
                // 数值区不参与 flex 分配：否则会与左侧 Expanded 平分剩余空
                // 间，导致右侧留白（数值与箭头被推到中间）。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    value!,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: p.textSecondary),
                  ),
                ),
              if (onTap != null && showChevron) ...[
                const SizedBox(width: 6),
                const FnChevron(size: 15),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 开关行：左图标 + 标题 + 右侧 Cupertino 开关。
class FnSwitchRow extends StatelessWidget {
  const FnSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    final canToggle = enabled && value != null;
    return SizedBox(
      height: 49,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: p.textSecondary),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, color: p.textPrimary),
              ),
            ),
            CupertinoSwitch(
              activeTrackColor: FnColors.primary,
              value: value ?? false,
              onChanged: canToggle ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级页面顶栏：左返回圆按钮 + 居中标题 + 右侧操作。
class FnPageBar extends StatelessWidget {
  const FnPageBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            FnHeaderButton(
              icon: CupertinoIcons.chevron_back,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: FnTextStyles.of(context).navTitle,
              ),
            ),
            SizedBox(width: 38, child: trailing),
          ],
        ),
      ),
    );
  }
}

/// 圆形图标按钮：默认 38×38 半透明底，可切透明/自定义尺寸。
class FnCircleIconButton extends StatelessWidget {
  const FnCircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.iconSize = 20,
    this.transparent = false,
    this.bordered = false,
    this.color,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool transparent;
  final bool bordered;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: transparent ? null : (background ?? p.overlayWeak),
            shape: BoxShape.circle,
            border: bordered ? Border.all(color: p.divider) : null,
          ),
          child: Icon(icon, size: iconSize, color: color ?? p.textPrimary),
        ),
      ),
    );
  }
}

/// 底部弹层的拖拽把手。
class FnSheetHandle extends StatelessWidget {
  const FnSheetHandle({super.key, this.width = 36, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color ?? p.trackFill,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// 状态胶囊：淡色底 + 同色文字，用于「空闲 / 进行中 / 本机」等状态提示。
class FnStatusChip extends StatelessWidget {
  const FnStatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 空态 / 错误态：柔光图标 + 标题 + 说明 + 可选操作按钮。
///
/// 整页空态用默认尺寸居中；列表分区内用 `compact` 缩小留白。
/// `isError` 打开时换成琥珀色图标，并通常配合「重试」按钮使用。
class FnEmptyState extends StatelessWidget {
  const FnEmptyState({
    super.key,
    required this.icon,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.isError = false,
    this.padding,
  });

  final IconData icon;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final bool isError;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = fnPaletteOf(context);
    final accent = isError ? FnColors.orange : FnColors.primary;
    final badge = compact ? 52.0 : 68.0;
    final iconSize = compact ? 24.0 : 30.0;

    return Padding(
      padding: padding ??
          EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 22 : 44),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.26),
                    accent.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: iconSize, color: accent),
            ),
            if (title != null && title!.isNotEmpty) ...[
              SizedBox(height: compact ? 11 : 15),
              Text(
                title!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 13.5 : 15.5,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
            if (message != null && message!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 12.5,
                    height: 1.45,
                    color: p.textSecondary,
                  ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 12 : 18),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: FnColors.primary,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: FnColors.primary.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: FnColors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 筛选胶囊（`.chips .c`）：30px 高、999 圆角、选中白底黑字。
class FnChip extends StatelessWidget {
  const FnChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: selected ? FnColors.textPrimary : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? FnColors.textPrimary : FnColors.overlayBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? FnColors.base : FnColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';

/// 页面左右留白。
const double kFnPad = 20;

/// 三档页面留白（design/v3 §5：mobile 20 / laptop 24 / desktop 28）。
double fnPagePad(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= kFnBpDesktop) return 28;
  if (w >= kFnBpLaptop) return 24;
  return kFnPad;
}

/// 底部导航高度（不含安全区，design/v3 tokens --tab-h）。
const double kFnTabH = 56;

/// 迷你播放器高度（design/v3 tokens --mini-h）。
const double kFnMiniH = 56;

/// Tab 页为悬浮 dock 预留的底部空间（不含 mini 条）。
const double kFnDockInset = kFnTabH;

/// mini 条是否在该路由展示：仅发现 / 曲库页（听歌页自带全屏播放，我的页不需要）。
bool fnMiniOnRoute(String location) =>
    location == '/discover' || location == '/library';

/// 底部 dock 实际高度：Tab 导航 +（mini 条展示时）mini 高度与间距。
double fnDockHOf(String location) =>
    kFnTabH + (fnMiniOnRoute(location) ? kFnMiniH + 8 : 0);

/// 封面氛围色相：由歌曲 id 稳定派生。
int fnHue(int seed) => (seed * 47) % 360;

/// 视差封面渐变：主色 + 深色第二色。
LinearGradient fnCoverGradient(int seed) {
  final h = fnHue(seed);
  return LinearGradient(
    begin: const Alignment(-0.6, -0.8),
    end: const Alignment(0.6, 0.8),
    colors: [
      HSLColor.fromAHSL(1, h.toDouble(), 0.68, 0.42).toColor(),
      HSLColor.fromAHSL(1, ((h + 302) % 360).toDouble(), 0.58, 0.22).toColor(),
    ],
  );
}

/// 封面下方的氛围光。
Color fnCoverGlow(int seed) =>
    HSLColor.fromAHSL(0.45, fnHue(seed).toDouble(), 0.7, 0.52).toColor();

String fmtDuration(double? sec) {
  if (sec == null || sec.isNaN || sec < 0) return '--:--';
  final m = sec ~/ 60;
  final s = (sec % 60).floor();
  return '$m:${s.toString().padLeft(2, '0')}';
}

String fmtSampleRate(int? sr) {
  if (sr == null || sr <= 0) return '-';
  final k = sr / 1000.0;
  return '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
}

String fmtCount(int n) {
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(n % 10000 == 0 ? 0 : 1)}万';
  return '$n';
}

/// 质量标签（PURE / HI-RES / DSD / LOSSY）。
({String label, Color color, String codec}) fnFormatOf(Song song) {
  final codec = (song.codec ?? '').toUpperCase();
  if (song.isDsd) return (label: 'DSD', color: FnColors.cyan, codec: codec);
  if (song.isHiRes) {
    return (
      label: 'HI-RES',
      color: FnColors.gold,
      codec: '${codec.isEmpty ? 'PCM' : codec} ${fmtSampleRate(song.sampleRate)}',
    );
  }
  if (song.isLossy) return (label: 'LOSSY', color: FnColors.textSecondary, codec: codec);
  return (label: 'PURE', color: FnColors.green, codec: codec.isEmpty ? 'FLAC' : codec);
}

/// 毛玻璃材质。
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
            color: color ?? FnColors.glass,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: content,
        ),
      ),
    );
    if (shadow == null) return clipped;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: clipped,
    );
  }
}

/// 网络封面：渐变占位 + 圆角 + 发丝内描边。
class FnCover extends StatelessWidget {
  const FnCover({
    super.key,
    required this.songId,
    this.size = 46,
    this.radius = 12,
    this.kind,
    this.hueSeed,
  });

  final int songId;
  final double size;
  final double radius;
  final String? kind;
  final int? hueSeed;

  @override
  Widget build(BuildContext context) {
    final seed = hueSeed ?? songId;
    if (size.isInfinite) {
      return LayoutBuilder(builder: (context, box) {
        final side = box.maxWidth.isFinite ? box.maxWidth : box.maxHeight;
        return _build(context, side.isFinite ? side : 46, seed);
      });
    }
    return _build(context, size, seed);
  }

  Widget _build(BuildContext context, double side, int seed) {
    // 按实际显示尺寸解码：库里都是原图（常见 1000px+，解码后每张 4MB 起），
    // 曲库列表反复滚动时大量原图同时驻留会让 iOS 被系统 OOM 杀掉。
    final int? px = side.isFinite
        ? (side * MediaQuery.devicePixelRatioOf(context)).round()
        : null;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: fnCoverGradient(seed),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: FnColors.isDark ? 0.35 : 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            ApiClient.instance.coverUrl(songId, kind: kind),
            fit: BoxFit.cover,
            cacheWidth: px,
            cacheHeight: px,
            errorBuilder: (_, __, ___) => _coverFallback(seed, side),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverFallback(int seed, double side) {
    return Center(
      child: Icon(
        CupertinoIcons.music_note_2,
        size: side * 0.34,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}

/// 圆形头像（艺人 / 用户）。
class FnAvatar extends StatelessWidget {
  const FnAvatar({
    super.key,
    required this.imageUrl,
    this.size = 52,
    this.fallbackIcon = CupertinoIcons.person_fill,
  });

  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: FnColors.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: FnColors.line2),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? Icon(fallbackIcon, size: size * 0.44, color: FnColors.textTertiary)
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                fallbackIcon,
                size: size * 0.44,
                color: FnColors.textTertiary,
              ),
            ),
    );
  }
}

/// 圆形图标按钮（38×38，半透明底 + 发丝描边）。
class FnIconBtn extends StatelessWidget {
  const FnIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.iconSize = 20,
    this.variant = FnIconBtnVariant.glass,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final FnIconBtnVariant variant;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bg = switch (variant) {
      FnIconBtnVariant.glass => FnColors.glassLight,
      FnIconBtnVariant.plain => Colors.transparent,
      FnIconBtnVariant.lime => FnColors.lime,
      FnIconBtnVariant.coral => FnColors.coralSoft,
      FnIconBtnVariant.dark => const Color(0x17FFFFFF),
    };
    final fg = color ??
        switch (variant) {
          FnIconBtnVariant.lime => FnColors.limeInk,
          FnIconBtnVariant.coral => FnColors.coral,
          FnIconBtnVariant.dark => Colors.white,
          _ => FnColors.textPrimary,
        };
    final btn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: variant == FnIconBtnVariant.glass ||
                  variant == FnIconBtnVariant.dark
              ? Border.all(
                  color: variant == FnIconBtnVariant.dark
                      ? const Color(0x1FFFFFFF)
                      : FnColors.line)
              : null,
        ),
        child: Icon(icon, size: iconSize, color: fg),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

enum FnIconBtnVariant { glass, plain, lime, coral, dark }

/// 页面大标题：eyebrow + h1 + 副标题 + 右侧操作。
class FnPageHead extends StatelessWidget {
  const FnPageHead({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = FnTextStyles.of(context);
    final pad = fnPagePad(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pad,
        MediaQuery.paddingOf(context).top + 8,
        pad,
        14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(eyebrow!.toUpperCase(), style: t.eyebrow),
                const SizedBox(height: 5),
                Text(title, style: t.h1),
                if (subtitle != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    subtitle!,
                    style:
                        TextStyle(fontSize: 12.5, color: FnColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 二级页顶栏：返回 + 居中标题 + 右侧操作，毛玻璃吸顶。
class FnNav extends StatelessWidget {
  const FnNav({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing = const <Widget>[],
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> trailing;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: FnColors.glass,
            border: Border(bottom: BorderSide(color: FnColors.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: showBack
                    ? FnIconBtn(
                        icon: CupertinoIcons.chevron_back,
                        size: 38,
                        iconSize: 19,
                        variant: FnIconBtnVariant.plain,
                        onTap: onBack ??
                            () => Navigator.of(context).maybePop(),
                      )
                    : null,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.16,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: FnColors.textTertiary,
                            fontFamily: FnText.monoFamily.first,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: trailing.isEmpty ? 38 : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < trailing.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      trailing[i],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 区块标题。
class FnSectionHead extends StatelessWidget {
  const FnSectionHead({
    super.key,
    required this.title,
    this.sub,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  final String title;
  final String? sub;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(kFnPad, 24, kFnPad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: FnTextStyles.of(context).h2),
                if (sub != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    sub!,
                    style:
                        TextStyle(fontSize: 11, color: FnColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FnColors.textSecondary,
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_forward,
                      size: 13, color: FnColors.textTertiary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 按钮：primary(青柠) / coral / soft / ghost。
class FnButton extends StatelessWidget {
  const FnButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.variant = FnButtonVariant.primary,
    this.size = FnButtonSize.md,
    this.block = false,
    this.enabled = true,
    this.dark = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final FnButtonVariant variant;
  final FnButtonSize size;
  final bool block;
  final bool enabled;

  /// 置于「始终深色区域」内（design/v3 §8）时固定使用深色调色板。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = dark ? fnDarkPalette : FnColors.palette;
    final height = switch (size) {
      FnButtonSize.sm => 34.0,
      FnButtonSize.md => 44.0,
      FnButtonSize.lg => 52.0,
    };
    final font = switch (size) {
      FnButtonSize.sm => 12.5,
      FnButtonSize.md => 14.0,
      FnButtonSize.lg => 15.0,
    };
    final (bg, fg) = switch (variant) {
      FnButtonVariant.primary => (p.lime, p.limeInk),
      FnButtonVariant.coral => (p.coral, Colors.white),
      FnButtonVariant.soft => (p.glassLight, p.textPrimary),
      FnButtonVariant.ghost => (Colors.transparent, p.textPrimary),
    };
    final child = Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: size == FnButtonSize.sm ? 14 : 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: variant == FnButtonVariant.soft
            ? Border.all(color: p.line2)
            : null,
        boxShadow: variant == FnButtonVariant.primary
            ? [
                BoxShadow(
                  color: p.lime.withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size == FnButtonSize.sm ? 15 : 18, color: fg),
            const SizedBox(width: 7),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: font,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: child,
      ),
    );
  }
}

enum FnButtonVariant { primary, coral, soft, ghost }

enum FnButtonSize { sm, md, lg }

/// 胶囊筛选 chip。
class FnChip extends StatelessWidget {
  const FnChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent = FnChipAccent.lime,
    this.small = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final FnChipAccent accent;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final onColor = accent == FnChipAccent.coral ? FnColors.coral : FnColors.lime;
    final onInk =
        accent == FnChipAccent.coral ? Colors.white : FnColors.limeInk;
    final fg = selected ? onInk : FnColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: small ? 27 : 32,
        padding: EdgeInsets.symmetric(horizontal: small ? 11 : 14),
        decoration: BoxDecoration(
          color: selected ? onColor : FnColors.glassLight,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: FnColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: small ? 12 : 14, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: small ? 11.5 : 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum FnChipAccent { lime, coral }

/// 分段控件。
class FnSegmented extends StatelessWidget {
  const FnSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.lime = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool lime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: FnColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FnColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(
                    color: i == index
                        ? (lime ? FnColors.lime : FnColors.surface)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: i == index && !lime
                        ? [
                            const BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 2))
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                      color: i == index
                          ? (lime ? FnColors.limeInk : FnColors.textPrimary)
                          : FnColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// v2 开关（44×26，选中青柠 + 深色滑块）。
class FnSwitch extends StatelessWidget {
  const FnSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          color: value ? FnColors.lime : FnColors.surface3,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? FnColors.limeInk : Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 格式徽标（PURE / Hi-Res / DSD / LOSSY）。
class FnFmtBadge extends StatelessWidget {
  const FnFmtBadge({super.key, required this.song, this.compact = false});

  final Song song;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = fnFormatOf(song);
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: f.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        compact ? f.label[0] : f.label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.34,
          fontFamily: FnText.monoFamily.first,
          color: f.color,
        ),
      ),
    );
  }
}

/// 歌曲行。
class FnSongRow extends StatelessWidget {
  const FnSongRow({
    super.key,
    required this.song,
    required this.onTap,
    this.onMore,
    this.onLongPress,
    this.ord,
    this.isCurrent = false,
    this.isPlaying = false,
    this.showDuration = true,
    this.subtitle,
    this.trailing,
    this.highlightCurrent = true,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final VoidCallback? onLongPress;
  final String? ord;
  final bool isCurrent;
  final bool isPlaying;
  final bool showDuration;
  final String? subtitle;
  final Widget? trailing;
  final bool highlightCurrent;

  @override
  Widget build(BuildContext context) {
    final titleColor = isCurrent && highlightCurrent
        ? FnColors.lime
        : FnColors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (ord != null)
              SizedBox(
                width: 20,
                child: isCurrent && isPlaying
                    ? _PlayingBars(color: FnColors.limeText)
                    : Text(
                        ord!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: FnText.monoFamily.first,
                          color: isCurrent && highlightCurrent
                              ? FnColors.lime
                              : FnColors.textTertiary,
                        ),
                      ),
              ),
            if (ord != null) const SizedBox(width: 9),
            FnCover(songId: song.id, size: 44, radius: 8),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle ?? song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: FnColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FnFmtBadge(song: song),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showDuration) ...[
              const SizedBox(width: 8),
              Text(
                fmtDuration(song.duration),
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textTertiary,
                ),
              ),
            ],
            if (onMore != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.more_horiz,
                      size: 18, color: FnColors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayingBars extends StatefulWidget {
  const _PlayingBars({required this.color});
  final Color color;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 1.5),
              Expanded(
                child: FractionallySizedBox(
                  heightFactor:
                      (0.35 + 0.65 * ((i * 0.3 + _c.value) % 1.0)).clamp(0.2, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(1),
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

/// 横向封面卡。
class FnArtCard extends StatelessWidget {
  const FnArtCard({
    super.key,
    required this.songId,
    required this.title,
    required this.sub,
    required this.onTap,
    this.width = 150,
    this.radius = 12,
    this.showPlayVeil = false,
  });

  final int songId;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final double width;
  final double radius;
  final bool showPlayVeil;

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
                FnCover(songId: songId, size: width, radius: radius),
                if (showPlayVeil)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: FnColors.lime,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: FnColors.lime.withValues(alpha: 0.4),
                              blurRadius: 18,
                            )
                          ],
                        ),
                        child: Icon(CupertinoIcons.play_fill,
                            size: 18, color: FnColors.limeInk),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: FnColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 艺人头像：无艺人图接口，用名称派生的渐变 + 首字母。
class FnArtistAvatar extends StatelessWidget {
  const FnArtistAvatar({super.key, required this.name, this.size = 52});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hue = (name.hashCode.abs() * 47) % 360;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.34).toColor(),
            HSLColor.fromAHSL(1, ((hue + 40) % 360).toDouble(), 0.45, 0.16)
                .toColor(),
          ],
        ),
        border: Border.all(color: FnColors.line2),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.86),
        ),
      ),
    );
  }
}

/// 流派磁贴高度（design/v3 `.genre-tile { height: 84px }`）。
///
/// 随系统字号放大，磁贴整体高度同步增加，避免固定高度把两行文字挤到溢出；
/// 使用磁贴的网格必须用 [SliverGridDelegateWithFixedCrossAxisCount.mainAxisExtent]
/// 取同一个值，不能用宽高比（宽高比会让窄窗口下的格子比内容还矮）。
double fnGenreTileHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(84).clamp(84.0, 132.0);

/// 流派磁贴：色相渐变卡。
class FnGenreTile extends StatelessWidget {
  const FnGenreTile({
    super.key,
    required this.name,
    required this.count,
    required this.onTap,
    this.hue,
  });

  final String name;
  final int count;
  final VoidCallback onTap;
  final int? hue;

  @override
  Widget build(BuildContext context) {
    final h = (hue ?? name.hashCode.abs() * 37 % 360).toDouble();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: fnGenreTileHeight(context),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HSLColor.fromAHSL(1, h, 0.45, 0.2).toColor(),
              FnColors.surface,
            ],
            stops: const [0, 0.85],
          ),
          border: Border.all(
              color: Colors.white.withValues(alpha: FnColors.isDark ? 0.08 : 0.4)),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$count 首',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.38,
                    fontFamily: FnText.monoFamily.first,
                    color: FnColors.textSecondary,
                  ),
                ),
              ],
            ),
            Positioned(
              right: -2,
              bottom: -4,
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 26,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 专辑格：封面 + 名称 + 艺人 · 年份 + 格式标签。
class FnAlbumCell extends StatelessWidget {
  const FnAlbumCell({
    super.key,
    required this.albumId,
    required this.name,
    required this.artist,
    required this.onTap,
    this.year,
    this.song,
  });

  final int albumId;
  final String name;
  final String artist;
  final VoidCallback onTap;
  final int? year;
  final Song? song;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: FnCover(
              songId: albumId,
              kind: 'album',
              size: double.infinity,
              radius: 14,
              hueSeed: albumId,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1),
          ),
          const SizedBox(height: 1),
          Text(
            year == null ? artist : '$artist · $year',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: FnColors.textSecondary),
          ),
          if (song != null) ...[
            const SizedBox(height: 5),
            Row(children: [FnFmtBadge(song: song!)]),
          ],
        ],
      ),
    );
  }
}

/// 歌单格：封面 + 曲目数角标 + 名称。
class FnPlaylistCell extends StatelessWidget {
  const FnPlaylistCell({
    super.key,
    required this.title,
    required this.count,
    required this.onTap,
    this.coverSongId,
    this.sub,
  });

  final String title;
  final int count;
  final VoidCallback onTap;
  final int? coverSongId;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                coverSongId == null
                    ? Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: fnCoverGradient(title.hashCode),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.queue_music_rounded,
                            size: 34, color: Colors.white54),
                      )
                    : FnCover(
                        songId: coverSongId!,
                        size: double.infinity,
                        radius: 16,
                        hueSeed: title.hashCode,
                      ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.4, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 9,
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.music_note_2,
                          size: 12, color: Colors.white70),
                      const SizedBox(width: 3),
                      Text(
                        '$count 首',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: FnText.monoFamily.first,
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (sub != null)
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: FnColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// 列表行：图标方块 + 标题/副标题 + 尾部值 + 箭头。
class FnListRow extends StatelessWidget {
  const FnListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.value,
    this.valueColor,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.showChevron = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String? value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? FnColors.coral : FnColors.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            if (icon != null)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: danger ? FnColors.coralSoft : FnColors.glassLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ??
                      (danger ? FnColors.coral : FnColors.textSecondary),
                ),
              ),
            if (icon != null) const SizedBox(width: 12),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: FnColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (value != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  value!,
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: valueColor ?? FnColors.textSecondary),
                ),
              ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            if (onTap != null && showChevron && trailing == null) ...[
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_forward,
                  size: 16, color: FnColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组卡：surface + 20 圆角 + 行间分隔线。
class FnGroupCard extends StatelessWidget {
  const FnGroupCard({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: kFnPad),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.md),
        border: Border.all(color: FnColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.only(left: 56),
                color: FnColors.line,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class FnGroupLabel extends StatelessWidget {
  const FnGroupLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(kFnPad, 22, kFnPad, 9),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.47,
          color: FnColors.textTertiary,
        ),
      ),
    );
  }
}

/// 统计方块。
class FnStatTile extends StatelessWidget {
  const FnStatTile({
    super.key,
    required this.value,
    required this.label,
    this.highlight = false,
    this.onTap,
  });

  final String value;
  final String label;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          gradient: highlight
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    FnColors.lime.withValues(alpha: 0.18),
                    FnColors.surface,
                  ],
                )
              : null,
          color: highlight ? null : FnColors.surface,
          borderRadius: BorderRadius.circular(FnRadius.sm),
          border: Border.all(color: FnColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.66,
                color: highlight ? FnColors.lime : FnColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: FnColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 快捷入口方块。
class FnQuickTile extends StatelessWidget {
  const FnQuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: FnColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: FnColors.line),
        ),
        child: Column(
          children: [
            Icon(icon, size: 21, color: FnColors.textPrimary),
            const SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: FnColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态。
class FnEmpty extends StatelessWidget {
  const FnEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.color,
    this.dark = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color? color;

  /// 固定在「始终深色区域」内使用（design/v3 §8），不随浅色主题变浅。
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = dark ? fnDarkPalette : FnColors.palette;
    final accent = color ?? p.lime;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 34, vertical: compact ? 26 : 52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: p.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: p.line),
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.textPrimary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 7),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: p.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FnButton(
                label: actionLabel!,
                onTap: onAction!,
                variant: FnButtonVariant.soft,
                size: FnButtonSize.sm,
                dark: dark),
          ],
        ],
      ),
    );
  }
}

/// 细进度条。
class FnProgressBar extends StatelessWidget {
  const FnProgressBar({
    super.key,
    required this.value,
    this.height = 3,
    this.color,
    this.trackColor,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: trackColor ?? FnColors.textFaint),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: ColoredBox(color: color ?? FnColors.lime),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可拖动进度条。
class FnScrubber extends StatefulWidget {
  const FnScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.height = 22,
    this.trackHeight = 4,
    this.buffered = 0,
    this.activeColor,
    this.trackColor,
    this.bufferedColor,
    this.timeStyle,
    this.showTime = true,
  });

  final double position;
  final double duration;
  final ValueChanged<double> onSeek;
  final double height;
  final double trackHeight;

  /// 已加载/已缓冲到的位置（秒），在进度条上单独叠加一层底色。
  final double buffered;
  final Color? activeColor;
  final Color? trackColor;
  final Color? bufferedColor;
  final TextStyle? timeStyle;

  /// 是否在进度条两端显示当前时间/总时长；外层已有时标签时可关闭。
  final bool showTime;

  @override
  State<FnScrubber> createState() => _FnScrubberState();
}

class _FnScrubberState extends State<FnScrubber> {
  /// 拖动中的目标位置（秒）：滑块跟手指走，不被外部周期刷新拉回。
  double? _drag;

  void _dragTo(Offset local, double width) {
    if (widget.duration <= 0) return;
    final sec = (local.dx / width).clamp(0.0, 1.0) * widget.duration;
    setState(() => _drag = sec);
  }

  void _endDrag() {
    final d = _drag;
    // 拖动过程只更新滑块，松手才真正 seek，避免频繁打断解码线程。
    if (d != null) widget.onSeek(d);
    setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final pos = _drag ?? widget.position;
    final ratio = widget.duration > 0
        ? (pos / widget.duration).clamp(0.0, 1.0)
        : 0.0;
    final bufferedRatio = widget.duration > 0
        ? (widget.buffered / widget.duration).clamp(0.0, 1.0)
        : 0.0;
    // 缓冲位置不应短于已播放位置（本地文件/投屏时引擎可能不上报缓冲）。
    final shownBuffered = bufferedRatio < ratio ? ratio : bufferedRatio;
    final bufferedColor =
        widget.bufferedColor ?? Colors.grey.shade400.withValues(alpha: 0.65);
    final time = widget.timeStyle ??
        TextStyle(
          fontSize: 10.5,
          fontFamily: FnText.monoFamily.first,
          color: FnColors.textSecondary,
        );
    return Row(
      children: [
        if (widget.showTime)
          SizedBox(width: 36, child: Text(fmtDuration(pos), style: time)),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              void tapSeek(Offset local) {
                if (widget.duration <= 0) return;
                final r = (local.dx / box.maxWidth).clamp(0.0, 1.0);
                widget.onSeek(r * widget.duration);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => tapSeek(d.localPosition),
                onHorizontalDragStart: (d) => _dragTo(d.localPosition, box.maxWidth),
                onHorizontalDragUpdate: (d) => _dragTo(d.localPosition, box.maxWidth),
                onHorizontalDragEnd: (_) => _endDrag(),
                onHorizontalDragCancel: _endDrag,
                child: SizedBox(
                  height: widget.height,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          height: widget.trackHeight,
                          decoration: BoxDecoration(
                            color: widget.trackColor ?? FnColors.textFaint,
                            borderRadius: BorderRadius.circular(widget.trackHeight),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: shownBuffered,
                          child: Container(
                            height: widget.trackHeight,
                            decoration: BoxDecoration(
                              color: bufferedColor,
                              borderRadius:
                                  BorderRadius.circular(widget.trackHeight),
                            ),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: widget.trackHeight,
                            decoration: BoxDecoration(
                              color: widget.activeColor ?? FnColors.lime,
                              borderRadius:
                                  BorderRadius.circular(widget.trackHeight),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.showTime)
          SizedBox(
            width: 36,
            child: Text(
              fmtDuration(widget.duration),
              textAlign: TextAlign.right,
              style: time,
            ),
          ),
      ],
    );
  }
}

/// 播放控制条：shuffle / prev / play / next / repeat。
class FnTransport extends StatelessWidget {
  const FnTransport({
    super.key,
    this.compact = false,
    this.showShuffle = true,
    this.showRepeat = true,
    this.color,
    this.playBackground,
    this.playForeground,
  });

  final bool compact;
  final bool showShuffle;
  final bool showRepeat;
  final Color? color;
  final Color? playBackground;
  final Color? playForeground;

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return StreamBuilder<void>(
      stream: c.stateChanges.stream,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showShuffle)
            _TButton(
              icon: Icons.shuffle_rounded,
              on: c.shuffle,
              onTap: c.toggleShuffle,
              color: color,
              size: compact ? 40 : 44,
              iconSize: compact ? 20 : 22,
            )
          else
            const SizedBox(width: 40),
          _TButton(
            icon: CupertinoIcons.backward_end_fill,
            iconSize: compact ? 21 : 24,
            onTap: c.prev,
            color: color,
            size: compact ? 40 : 44,
          ),
          GestureDetector(
            onTap: c.togglePlay,
            child: Container(
              width: compact ? 58 : 66,
              height: compact ? 58 : 66,
              decoration: BoxDecoration(
                color: playBackground ?? FnColors.lime,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (playBackground ?? FnColors.lime)
                        .withValues(alpha: 0.45),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: compact ? 26 : 30,
                color: playForeground ?? FnColors.limeInk,
              ),
            ),
          ),
          _TButton(
            icon: CupertinoIcons.forward_end_fill,
            iconSize: compact ? 21 : 24,
            onTap: c.next,
            color: color,
            size: compact ? 40 : 44,
          ),
          if (showRepeat)
            _TButton(
              icon: c.repeat == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              on: c.repeat != LoopMode.off,
              onTap: c.cycleRepeat,
              color: color,
              size: compact ? 40 : 44,
              iconSize: compact ? 20 : 22,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _TButton extends StatelessWidget {
  const _TButton({
    required this.icon,
    required this.onTap,
    this.on = false,
    this.color,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool on;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          size: iconSize,
          color: on ? FnColors.lime : (color ?? FnColors.textPrimary),
        ),
      ),
    );
  }
}

/// 页脚说明。
class FnPageFoot extends StatelessWidget {
  const FnPageFoot({super.key, required this.left, this.right, this.onRight});

  final String left;
  final String? right;
  final VoidCallback? onRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(fnPagePad(context), 30, fnPagePad(context), 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.38,
                fontFamily: FnText.monoFamily.first,
                color: FnColors.textTertiary,
              ),
            ),
          ),
          if (right != null)
            GestureDetector(
              onTap: onRight,
              child: Text(
                right!,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.38,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.limeText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部弹层外框。
class FnSheetFrame extends StatelessWidget {
  const FnSheetFrame({
    super.key,
    this.eyebrow,
    this.title,
    this.subtitle,
    required this.children,
    this.footer,
  });

  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(FnRadius.lg)),
        border: Border(top: BorderSide(color: FnColors.line2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              color: FnColors.textFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null)
                          Text(
                            eyebrow!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.43,
                              color: FnColors.textTertiary,
                            ),
                          ),
                        if (eyebrow != null) const SizedBox(height: 2),
                        Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: TextStyle(
                                fontSize: 11.5, color: FnColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  FnIconBtn(
                    icon: Icons.close_rounded,
                    size: 32,
                    iconSize: 18,
                    variant: FnIconBtnVariant.plain,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  12, title == null ? 12 : 0, 12, 12),
              child: Column(children: children),
            ),
          ),
          if (footer != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  16, 10, 16, 14 + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: FnColors.line)),
              ),
              child: footer,
            ),
          if (footer == null)
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

/// 弹层选项行。
class FnOptionRow extends StatelessWidget {
  const FnOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.on = false,
    this.tag,
    this.danger = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool on;
  final String? tag;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            if (icon != null)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: danger ? FnColors.coralSoft : FnColors.glassLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 19,
                    color: danger ? FnColors.coral : FnColors.textSecondary),
              ),
            if (icon != null) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: danger ? FnColors.coral : FnColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                          fontSize: 11, color: FnColors.textSecondary),
                    ),
                ],
              ),
            ),
            if (tag != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: FnColors.limeSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag!,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: FnText.monoFamily.first,
                    color: FnColors.limeText,
                  ),
                ),
              ),
            if (on) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 19, color: FnColors.limeText),
            ],
          ],
        ),
      ),
    );
  }
}

/// 弹层展示。
Future<T?> showFnSheet<T>(
  BuildContext context, {
  required List<Widget> children,
  String? eyebrow,
  String? title,
  String? subtitle,
  Widget? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: FnColors.barrier,
    builder: (ctx) => FnSheetFrame(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      footer: footer,
      children: children,
    ),
  );
}

/// 轻提示：统一走 Material SnackBar（外观由 `snackBarTheme` 控制）。
void fnToast(BuildContext context, String message, {IconData? icon}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 1800),
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: FnColors.limeText),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 沉浸页背景：模糊封面 + 氛围光 + 暗角（design/v3 `.fn-stage-bg`）。
class FnStageBackground extends StatelessWidget {
  const FnStageBackground({super.key, required this.song, this.blur = 42});

  final Song song;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final hue = fnHue(song.id).toDouble();
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.scale(
              scale: 1.12,
              child: Image.network(
                ApiClient.instance.coverUrl(song.id),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: fnCoverGradient(song.id),
                  ),
                ),
              ),
            ),
          ),
          // 封面色相氛围光。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 1.1,
                colors: [
                  HSLColor.fromAHSL(0.24, hue, 0.7, 0.45).toColor(),
                  Colors.transparent,
                ],
                stops: const [0, 0.62],
              ),
            ),
          ),
          // 由浅入深的暗角，保证页内文字对比度。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.9),
                  Colors.black,
                ],
                stops: const [0, 0.45, 0.82, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部大标题滚动吸顶辅助：返回当前滚动偏移。
class FnScrollHead extends StatelessWidget {
  const FnScrollHead({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return FnPageHead(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      actions: actions,
    );
  }
}

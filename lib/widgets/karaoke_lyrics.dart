import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../player_controller.dart';
import '../theme.dart';

/// 每行歌词的最小占位高度（单行文本时保持原有留白）。
const double _minLyricLineHeight = 58;
/// 文本实际高度之外再留出的行间距。
const double _lyricLinePadding = 16;
/// 歌词左右各留出的边距，绘制与测量共用，保证换行位置一致。
const double _lyricSideInset = 24;

/// 测量一行歌词占用的高度：单行时取固定留白，换行后按实际行数撑开。
double _measureLyricBlock(
  String text,
  double fontSize,
  FontWeight weight,
  double maxWidth,
) {
  final tp = TextPainter(
    text: TextSpan(
      text: text.isEmpty ? '♪' : text,
      style: TextStyle(fontSize: fontSize, fontWeight: weight, height: 1.4),
    ),
    textDirection: ui.TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: math.max(1, maxWidth));
  return math.max(_minLyricLineHeight, tp.height + _lyricLinePadding);
}

/// 卡拉OK 式逐字歌词（Canvas 绘制）。
/// LRC 只有行级时间戳，行内按到下一行的时间间隔线性插值做逐字扫色。
class KaraokeLyrics extends StatefulWidget {
  final int songId;
  const KaraokeLyrics({super.key, required this.songId});

  @override
  State<KaraokeLyrics> createState() => _KaraokeLyricsState();
}

class _KaraokeLyricsState extends State<KaraokeLyrics> {
  final _controller = PlayerController.instance;
  List<LyricLine> _lines = []; // 带时间轴的行（卡拉OK扫色）
  List<LyricLine> _plainLines = []; // 纯文本歌词行（无时间轴）
  bool _loading = true;
  String? _error; // 请求失败原因（网络错误 / 未登录）
  int _active = -1;
  double _progress = 0; // 当前行内扫色进度 0..1
  double _scrollOffset = 0; // 目标滚动偏移（active 行居中）
  double _renderedOffset = 0;
  Timer? _timer;
  double _height = 0;
  double _width = 0;
  int? _userScrollUntil;
  int? _userSeekLine;
  // 按当前宽度测量出的每行占位高度：普通态与高亮态分别测量，换行后自动撑开。
  double _metricsWidth = -1;
  List<double> _normalHeights = const [];
  List<double> _activeHeights = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant KaraokeLyrics old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _active = -1;
      _renderedOffset = 0;
      _scrollOffset = 0;
    });
    try {
      final data = await ApiClient.instance.fetchLyric(widget.songId);
      if (!mounted) return;
      final timed = data.lines.where((l) => l.timeMs != null).toList();
      final plain = data.lines
          .where((l) => l.timeMs == null && l.text.trim().isNotEmpty)
          .toList();
      setState(() {
        _lines = timed;
        _plainLines = timed.isEmpty ? plain : const [];
        _loading = false;
        _metricsWidth = -1;
        _normalHeights = const [];
        _activeHeights = const [];
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _tick() {
    if (!mounted || _lines.isEmpty) return;
    final posMs = _controller.positionSec * 1000;
    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if ((_lines[i].timeMs ?? 0) <= posMs) {
        idx = i;
      } else {
        break;
      }
    }
    var prog = 0.0;
    if (idx >= 0) {
      final start = _lines[idx].timeMs ?? 0;
      final end = idx + 1 < _lines.length
          ? (_lines[idx + 1].timeMs ?? start + 4000)
          : start + 4000;
      prog =
          end > start ? ((posMs - start) / (end - start)).clamp(0.0, 1.0) : 1.0;
    }
    if (idx != _active || (prog - _progress).abs() > 0.002) {
      setState(() {
        _active = idx;
        _progress = prog;
        _scrollOffset = _scrollTargetFor(idx);
      });
    }
    // 平滑滚动
    if ((_renderedOffset - _scrollOffset).abs() > 0.5) {
      setState(() {
        _renderedOffset += (_scrollOffset - _renderedOffset) * 0.18;
      });
    }
    // 用户点击后短暂高亮他点的行，再恢复自动滚动
    if (_userScrollUntil != null &&
        DateTime.now().millisecondsSinceEpoch > _userScrollUntil!) {
      _userSeekLine = null;
      _userScrollUntil = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 按当前可用宽度测量每行高度；只有宽度或歌词内容变化时才重新计算。
  /// 返回是否重新测量，便于调用方同步修正滚动偏移。
  bool _ensureMetrics(double width) {
    final usable = math.max(1.0, width - _lyricSideInset * 2);
    if (_metricsWidth == usable && _normalHeights.length == _lines.length) {
      return false;
    }
    _metricsWidth = usable;
    _normalHeights = [
      for (final line in _lines)
        _measureLyricBlock(line.text, 16.0, FontWeight.w400, usable),
    ];
    _activeHeights = [
      for (final line in _lines)
        _measureLyricBlock(line.text, 21.0, FontWeight.w700, usable),
    ];
    return true;
  }

  bool get _metricsReady => _normalHeights.length == _lines.length;

  double _lineHeightAt(int index) {
    if (!_metricsReady) return _minLyricLineHeight;
    return _active == index ? _activeHeights[index] : _normalHeights[index];
  }

  double _lineTop(int index) {
    if (!_metricsReady) return index * _minLyricLineHeight;
    var y = 0.0;
    final end = math.min(index, _lines.length);
    for (var i = 0; i < end; i++) {
      y += _active == i ? _activeHeights[i] : _normalHeights[i];
    }
    return y;
  }

  /// 高亮行居中所需的滚动偏移，并限制在内容范围内，避免末尾滚出空白。
  double _scrollTargetFor(int index) {
    if (index < 0 || !_metricsReady || _height <= 0) return 0;
    final maxOffset = math.max(0.0, _lineTop(_lines.length) - _height);
    final target = _lineTop(index) + _lineHeightAt(index) / 2 - _height / 2;
    return target.clamp(0.0, maxOffset);
  }

  void _onTapDown(TapDownDetails d) {
    if (_height == 0 || !_metricsReady) return;
    final localY = d.localPosition.dy + _renderedOffset;
    var top = 0.0;
    for (var i = 0; i < _lines.length; i++) {
      final bottom = top + _lineHeightAt(i);
      if (localY >= top && localY < bottom) {
        final t = _lines[i].timeMs;
        if (t != null) {
          _controller.seek(t / 1000);
          setState(() {
            _userSeekLine = i;
            _userScrollUntil = DateTime.now().millisecondsSinceEpoch + 2000;
          });
        }
        return;
      }
      top = bottom;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null) {
      // 明确区分"网络/鉴权错误"和"没有歌词"，避免静默显示"暂无歌词"。
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle,
                size: 44, color: FnColors.textTertiary),
            const SizedBox(height: 12),
            Text(context.l10n.lyricsLoadFailed,
                style: TextStyle(color: FnColors.textSecondary)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: FnColors.textTertiary)),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              onPressed: _load,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.arrow_counterclockwise,
                      size: 18, color: FnColors.primary),
                  const SizedBox(width: 6),
                  Text(context.l10n.commonRetry,
                      style: TextStyle(
                          fontSize: 15, color: FnColors.primary)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_lines.isEmpty && _plainLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.text_alignleft,
                size: 48, color: FnColors.textTertiary),
            const SizedBox(height: 12),
            Text(context.l10n.noLyrics,
                style: TextStyle(color: FnColors.textSecondary)),
            const SizedBox(height: 6),
            Text(context.l10n.noLyricsHint,
                style: TextStyle(fontSize: 11, color: FnColors.textTertiary)),
          ],
        ),
      );
    }
    // 无时间轴的纯文本歌词：静态滚动展示。
    if (_lines.isEmpty) {
      return ListView.separated(
        itemCount: _plainLines.length,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, i) {
          final text = _plainLines[i].text;
          return Text(
            text.isEmpty ? '♪' : text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16, color: FnColors.textSecondary, height: 1.5),
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        _width = constraints.maxWidth;
        if (_ensureMetrics(_width)) {
          // 尺寸或歌词变化后重新对齐高亮行，避免仍停留在旧的行高位置上。
          _scrollOffset = _scrollTargetFor(_active);
          _renderedOffset = _scrollOffset;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          child: CustomPaint(
            size: Size.infinite,
            painter: _KaraokePainter(
              lines: _lines,
              active: _active,
              progress: _progress,
              offset: _renderedOffset,
              width: _width,
              userSeekLine: _userSeekLine,
              normalHeights: _normalHeights,
              activeHeights: _activeHeights,
              textColor: FnColors.textPrimary,
              dimColor: FnColors.textTertiary,
              sweepColors: FnColors.lyricSweep,
            ),
          ),
        );
      },
    );
  }
}

class _KaraokePainter extends CustomPainter {
  final List<LyricLine> lines;
  final int active;
  final double progress;
  final double offset;
  final double width;
  final int? userSeekLine;
  /// 每行实际占位高度（按换行后的文本测量），用于排布与裁剪。
  final List<double> normalHeights;
  final List<double> activeHeights;

  /// 绘制时读的主题色：切换深浅主题后 [shouldRepaint] 据此判断需要重绘。
  final Color textColor;
  final Color dimColor;

  /// 已唱部分的三色渐变（左 → 右），见 [FnColors.lyricSweep] 配置。
  final List<Color> sweepColors;

  _KaraokePainter({
    required this.lines,
    required this.active,
    required this.progress,
    required this.offset,
    required this.width,
    required this.userSeekLine,
    required this.normalHeights,
    required this.activeHeights,
    required this.textColor,
    required this.dimColor,
    required this.sweepColors,
  });

  double _heightAt(int index) {
    if (normalHeights.length != lines.length) return _minLyricLineHeight;
    return index == active ? activeHeights[index] : normalHeights[index];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final maxWidth = math.max(1.0, width - _lyricSideInset * 2);
    var top = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final lineHeight = _heightAt(i);
      final y = top - offset;
      top += lineHeight;
      if (y + lineHeight < 0 || y > size.height + lineHeight) continue;

      final text = lines[i].text.isEmpty ? '♪' : lines[i].text;
      final isActive = i == active;
      final isUserSeek = i == userSeekLine;
      final fontSize = isActive ? 21.0 : 16.0;
      // 未扫部分用主文字色（浅色主题下不能用白色，否则白底白字不可见）。
      final baseColor =
          isActive ? textColor : (isUserSeek ? FnColors.primary : dimColor);

      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: baseColor,
            height: 1.4,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxWidth);

      final dx = (size.width - tp.width) / 2;
      final dy = y + (lineHeight - tp.height) / 2;

      if (isActive) {
        // 先画整行白色（未扫部分）
        tp.paint(canvas, Offset(dx, dy));
        final tpSweep = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1.4,
              // 扫色层用三色横向渐变（配置在 FnColors.lyricSweep）。
              foreground: Paint()
                ..shader = ui.Gradient.linear(
                  Offset(dx, dy),
                  Offset(dx + math.max(1.0, tp.width), dy),
                  sweepColors,
                  const [0.0, 0.5, 1.0],
                ),
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: maxWidth);
        // 按扫色进度裁剪出渐变覆盖层：换行后逐行推进，避免整块矩形提前盖到下一行。
        final lineMetrics = tp.computeLineMetrics();
        final totalWidth =
            lineMetrics.fold<double>(0, (sum, m) => sum + m.width);
        var remaining = totalWidth * progress;
        var lineTop = 0.0;
        for (final m in lineMetrics) {
          if (remaining <= 0) break;
          final sweepW = math.min(remaining, m.width);
          if (sweepW > 0) {
            canvas.save();
            canvas.clipRect(Rect.fromLTWH(
                dx + m.left - 2, dy + lineTop - 2, sweepW + 4, m.height + 4));
            tpSweep.paint(canvas, Offset(dx, dy));
            canvas.restore();
          }
          remaining -= m.width;
          lineTop += m.height;
        }
      } else {
        tp.paint(canvas, Offset(dx, dy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KaraokePainter old) =>
      old.lines != lines ||
      old.width != width ||
      old.normalHeights != normalHeights ||
      old.activeHeights != activeHeights ||
      old.active != active ||
      old.progress != progress ||
      old.offset != offset ||
      old.userSeekLine != userSeekLine ||
      old.textColor != textColor ||
      old.dimColor != dimColor ||
      old.sweepColors != sweepColors;
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../player_controller.dart';
import '../theme.dart';

/// 卡拉OK 式逐字歌词（Canvas 绘制）。
/// LRC 只有行级时间戳，行内按到下一行的时间间隔线性插值做逐字扫色。
class KaraokeLyrics extends StatefulWidget {
  final int songId;
  const KaraokeLyrics({super.key, required this.songId});

  @override
  State<KaraokeLyrics> createState() => _KaraokeLyricsState();
}

class _KaraokeLyricsState extends State<KaraokeLyrics> {
  static const double _lineHeight = 58;

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
        _scrollOffset = (idx * _lineHeight - _height / 2 + _lineHeight / 2)
            .clamp(0, double.infinity);
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

  void _onTapDown(TapDownDetails d) {
    if (_height == 0) return;
    final localY = d.localPosition.dy + _renderedOffset;
    final idx = (localY / _lineHeight).floor();
    if (idx >= 0 && idx < _lines.length) {
      final t = _lines[idx].timeMs;
      if (t != null) {
        _controller.seek(t / 1000);
        setState(() {
          _userSeekLine = idx;
          _userScrollUntil = DateTime.now().millisecondsSinceEpoch + 2000;
        });
      }
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
              textColor: FnColors.textPrimary,
              dimColor: FnColors.textTertiary,
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

  /// 绘制时读的主题色：切换深浅主题后 [shouldRepaint] 据此判断需要重绘。
  final Color textColor;
  final Color dimColor;

  _KaraokePainter({
    required this.lines,
    required this.active,
    required this.progress,
    required this.offset,
    required this.width,
    required this.userSeekLine,
    required this.textColor,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const lineHeight = _KaraokeLyricsState._lineHeight;
    for (var i = 0; i < lines.length; i++) {
      final y = i * lineHeight - offset;
      if (y < -lineHeight || y > size.height + lineHeight) continue;

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
      )..layout(maxWidth: width - 48);

      final dx = (size.width - tp.width) / 2;
      final dy = y + (lineHeight - tp.height) / 2;

      if (isActive) {
        // 先画整行白色（未扫部分）
        tp.paint(canvas, Offset(dx, dy));
        // 再按扫色进度裁剪出 teal 覆盖层
        final sweepW = tp.width * progress;
        canvas.save();
        canvas
            .clipRect(Rect.fromLTWH(dx - 2, dy - 2, sweepW + 4, tp.height + 4));
        final tpSweep = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: FnColors.primary,
              height: 1.4,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: width - 48);
        tpSweep.paint(canvas, Offset(dx, dy));
        canvas.restore();
      } else {
        tp.paint(canvas, Offset(dx, dy));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KaraokePainter old) =>
      old.active != active ||
      old.progress != progress ||
      old.offset != offset ||
      old.userSeekLine != userSeekLine ||
      old.textColor != textColor ||
      old.dimColor != dimColor;
}

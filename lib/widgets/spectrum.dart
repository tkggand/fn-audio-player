import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fn_audio_engine/fn_audio_engine.dart' show engineSpectrum;

import '../player_controller.dart';
import '../theme.dart';

/// 播放频谱：对齐 Web 端 `Spectrum.tsx` 的 28 段柱状图。
///
/// 真实频谱只来自本地音频引擎（Rust 输出回调里的 PCM）；
/// 系统播放器（just_audio）拿不到 PCM，因此未播放或未启用本地引擎时
/// 显示 Web 同款静止示意柱，不做任何合成动画。
class PlaybackSpectrum extends StatefulWidget {
  const PlaybackSpectrum({
    super.key,
    this.bars = 28,
    this.height = 74,
    this.showAxis = true,
  });

  final int bars;
  final double height;
  final bool showAxis;

  @override
  State<PlaybackSpectrum> createState() => _PlaybackSpectrumState();
}

class _PlaybackSpectrumState extends State<PlaybackSpectrum>
    with SingleTickerProviderStateMixin {
  /// 未播放时的示意柱高（与 Web 端 IDLE 同形）。
  static const _idle = [46, 62, 54, 78, 92, 86, 70, 58, 44, 32];
  /// 频段坐标轴（与设计稿 SPEC_LB 一致）。
  static const _axis = [
    '20Hz', '63Hz', '125Hz', '250Hz', '500Hz',
    '1kHz', '2kHz', '4kHz', '8kHz', '16kHz',
  ];

  late final Ticker _ticker;
  List<double> _values = const [];

  @override
  void initState() {
    super.initState();
    _values = _idleValues();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<double> _idleValues() => [
        for (var i = 0; i < widget.bars; i++)
          _idle[i % _idle.length] / 100.0,
      ];

  void _tick() {
    if (!mounted) return;
    final pc = PlayerController.instance;
    final live = pc.usingLocalEngine && pc.isPlaying;
    final next = live ? _fromEngine() : _idleValues();
    if (listEquals(next, _values)) return;
    setState(() => _values = next);
  }

  List<double> _fromEngine() {
    final raw = engineSpectrum();
    if (raw.length < widget.bars) return _idleValues();
    final step = raw.length / widget.bars;
    return [
      for (var i = 0; i < widget.bars; i++)
        raw[(i * step).floor()].toDouble(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: CustomPaint(painter: _SpectrumPainter(values: _values)),
        ),
        Container(height: 1, color: FnColors.line),
        if (widget.showAxis) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (final t in _axis)
                Expanded(
                  child: Text(
                    t,
                    style: TextStyle(
                      fontSize: 10,
                      color: FnColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    const gap = 4.0;
    final bw = (size.width - gap * (n - 1)) / n;
    if (bw <= 0) return;

    // 与 Web 同配色：自下而上 绿 → 黄 → 珊瑚。
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [FnColors.green, FnColors.gold, FnColors.coral],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(Offset.zero & size);

    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final bh = (v * size.height).clamp(3.0, size.height);
      canvas.drawRect(
        Rect.fromLTWH(i * (bw + gap), size.height - bh, bw, bh),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      !listEquals(oldDelegate.values, values);
}

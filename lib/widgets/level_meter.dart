import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/l10n.dart';
import '../theme.dart';

/// 播放电平表：L / R / TP 三档，播放详情页展示（对齐 Web 稿的实时电平）。
///
/// just_audio 在桌面/移动端均不暴露 PCM 回调，无法对真实音频做 FFT；这里用
/// 播放器状态（是否在播、音量）驱动的本地合成信号计算相对电平，纯客户端渲染，
/// 不依赖后端任何新能力。未播放时归零到 −60 dB。
class PlaybackLevelMeter extends StatefulWidget {
  const PlaybackLevelMeter({
    super.key,
    required this.playing,
    required this.volume,
    required this.hasSong,
  });

  final bool playing;
  final double volume;
  final bool hasSong;

  @override
  State<PlaybackLevelMeter> createState() => _PlaybackLevelMeterState();
}

class _PlaybackLevelMeterState extends State<PlaybackLevelMeter>
    with SingleTickerProviderStateMixin {
  static const _floorDb = -60.0;

  late final Ticker _ticker;
  double _t = 0;
  double _l = _floorDb;
  double _r = _floorDb;
  double _tp = _floorDb;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _t = elapsed.inMilliseconds / 1000.0;
    final active = widget.hasSong && widget.playing;
    final target = active ? _synth(_t) : (_floorDb, _floorDb);
    // 上升快、回落慢，模拟电平表观感。
    final l = target.$1 > _l ? target.$1 : _l + (target.$1 - _l) * 0.16;
    final r = target.$2 > _r ? target.$2 : _r + (target.$2 - _r) * 0.16;
    final tp = math.max(l, r) + 1.2;
    setState(() {
      _l = l;
      _r = r;
      _tp = math.min(0, tp);
    });
  }

  /// 本地合成双声道电平（dBFS），带轻微声道差异与呼吸感。
  (double, double) _synth(double t) {
    final gain = (widget.volume <= 0 ? 0.0 : widget.volume).clamp(0.0, 1.0);
    if (gain == 0) return (_floorDb, _floorDb);
    final base = -14 + 9 * math.sin(t * 2.1);
    final l = base + 3 * math.sin(t * 5.7) - 6 * (1 - gain);
    final r = base + 3 * math.sin(t * 4.3 + 1.1) - 6 * (1 - gain);
    return (l.clamp(_floorDb, -1.0), r.clamp(_floorDb, -1.0));
  }

  static String _fmtDb(double db) =>
      db <= _floorDb ? '−∞' : '${db.toStringAsFixed(1)} dB';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.levelMeter,
            style: TextStyle(
                fontSize: 11,
                color: FnColors.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4)),
        const SizedBox(height: 6),
        _row('L', _l, FnColors.green),
        const SizedBox(height: 4),
        _row('R', _r, FnColors.green),
        const SizedBox(height: 4),
        _row('TP', _tp, _tp >= -1 ? FnColors.orange : FnColors.blue),
      ],
    );
  }

  Widget _row(String label, double db, Color color) {
    final ratio = ((db - _floorDb) / -_floorDb).clamp(0.0, 1.0);
    final warn = label != 'TP' ? db >= -3 : db >= -1;
    return Row(
      children: [
        SizedBox(
          width: 22,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: FnColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 6,
              color: FnColors.trackFill,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(color: warn ? FnColors.red : color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(_fmtDb(db),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: FnColors.textTertiary)),
        ),
      ],
    );
  }
}

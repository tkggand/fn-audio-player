import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// 与 Web 端 `web/src/components/Icon.tsx` 同源的线性图标。
///
/// 直接使用设计稿的 SVG path（24×24 视框、1.6px 圆端点），避免 Unicode 字形在
/// 各平台字重/基线不一致的问题；填充图形与描边图形分别按 Web 的 `class="st"` 规则绘制。
enum FnIconName {
  music,
  library,
  dsp,
  rg,
  eq,
  codec,
  airplay,
  volume,
  device,
}

/// 单个图形：描边（st）或填充。
abstract class _Shape {
  const _Shape(this.stroke);
  final bool stroke;
  Path build();
}

class _PathShape extends _Shape {
  const _PathShape(this.d, {bool stroke = false}) : super(stroke);
  final String d;
  @override
  Path build() => _parsePath(d);
}

class _CircleShape extends _Shape {
  const _CircleShape(this.cx, this.cy, this.r, {bool stroke = false})
      : super(stroke);
  final double cx, cy, r;
  @override
  Path build() =>
      Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

class _EllipseShape extends _Shape {
  const _EllipseShape(this.cx, this.cy, this.rx, this.ry, {bool stroke = false})
      : super(stroke);
  final double cx, cy, rx, ry;
  @override
  Path build() => Path()
    ..addOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
}

class _RectShape extends _Shape {
  const _RectShape(this.x, this.y, this.w, this.h, this.r,
      {bool stroke = false})
      : super(stroke);
  final double x, y, w, h, r;
  @override
  Path build() => Path()
    ..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));
}

const Map<FnIconName, List<_Shape>> _icons = {
  // 音符（源文件）
  FnIconName.music: [
    _PathShape('M9 17.6V7.2l9-1.7v10.3'),
    _EllipseShape(6.8, 17.8, 2.6, 2.2),
    _EllipseShape(15.8, 16.1, 2.6, 2.2),
  ],
  // 书架（解码）
  FnIconName.library: [
    _PathShape('M3.6 6.2h3.1v11.6H3.6z'),
    _PathShape('M9 4.6h3.1v13.2H9z'),
    _PathShape('M14.7 5.4l3-.6 3 13.6-3 .6z'),
  ],
  // 波形（重采样 / 音效预设）
  FnIconName.dsp: [
    _PathShape('M3 12h2.2l2-6 3 13 3-15 2.6 12 1.8-4H21', stroke: true),
  ],
  // 增益（ReplayGain）
  FnIconName.rg: [
    _PathShape('M4 9.5v5h3.4L12 18V6L7.4 9.5z', stroke: true),
    _PathShape('M15.4 9.2a4 4 0 0 1 0 5.6M18 6.8a7.6 7.6 0 0 1 0 10.4',
        stroke: true),
  ],
  // 均衡器
  FnIconName.eq: [
    _PathShape('M4 8h4.5M13 8h7M4 16h9M17.5 16H20', stroke: true),
    _CircleShape(11, 8, 2.4, stroke: true),
    _CircleShape(15.5, 16, 2.4, stroke: true),
  ],
  // 传输 / 编码（HTTP 流）
  FnIconName.codec: [
    _RectShape(6.5, 6.5, 11, 11, 2.2, stroke: true),
    _PathShape(
        'M10 3.5v3M14 3.5v3M10 17.5v3M14 17.5v3M3.5 10h3M3.5 14h3M17.5 10h3M17.5 14h3',
        stroke: true),
  ],
  // AirPlay（DLNA 推送）
  FnIconName.airplay: [
    _PathShape(
        'M5.4 16.4A2.6 2.6 0 0 1 5 11.2a6.4 6.4 0 0 1 12.3-1.4 3.6 3.6 0 0 1-.5 7.1',
        stroke: true),
    _PathShape('m12 14.2 3.6 5.4H8.4z', stroke: true),
  ],
  // 音量
  FnIconName.volume: [
    _PathShape(
        'M11 5.4 6.8 8.8H4.2a.9.9 0 0 0-.9.9v4.6a.9.9 0 0 0 .9.9h2.6L11 18.6z',
        stroke: true),
    _PathShape('M14.6 9.4a3.6 3.6 0 0 1 0 5.2M17 7a7 7 0 0 1 0 10',
        stroke: true),
  ],
  // 输出设备
  FnIconName.device: [
    _RectShape(3.5, 9, 17, 8.5, 2.4, stroke: true),
    _CircleShape(16.6, 13.2, 2.2, stroke: true),
    _PathShape('M6.6 13.2h.01', stroke: true),
  ],
};

/// 线性图标组件：按 [size] 缩放，使用 [color] 着色。
class FnIcon extends StatelessWidget {
  const FnIcon(this.name, {super.key, this.size = 20, this.color});

  final FnIconName name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _FnIconPainter(
          name: name,
          color: color ??
              DefaultTextStyle.of(context).style.color ??
              FnColors.textPrimary,
        ),
      ),
    );
  }
}

class _FnIconPainter extends CustomPainter {
  _FnIconPainter({required this.name, required this.color});
  final FnIconName name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final s in _icons[name]!) {
      canvas.drawPath(s.build(), s.stroke ? stroke : fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FnIconPainter old) =>
      old.name != name || old.color != color;
}

// ---------- 极简 SVG path 解析（仅覆盖本图标集用到的命令） ----------

final _cmdRe = RegExp(r'([MmLlHhVvAaZz])([^MmLlHhVvAaZz]*)');
final _numRe = RegExp(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

Path _parsePath(String d) {
  final path = Path();
  double cx = 0, cy = 0, sx = 0, sy = 0;
  for (final m in _cmdRe.allMatches(d)) {
    final cmd = m[1]!;
    final args = _numRe
        .allMatches(m[2]!)
        .map((e) => double.parse(e[0]!))
        .toList(growable: false);
    var i = 0;
    switch (cmd) {
      case 'M':
      case 'm':
        var first = true;
        while (i + 1 < args.length) {
          final x = args[i], y = args[i + 1];
          i += 2;
          if (cmd == 'M') {
            cx = x;
            cy = y;
          } else {
            cx += x;
            cy += y;
          }
          if (first) {
            path.moveTo(cx, cy);
            sx = cx;
            sy = cy;
            first = false;
          } else {
            path.lineTo(cx, cy);
          }
        }
        break;
      case 'L':
      case 'l':
        while (i + 1 < args.length) {
          final x = args[i], y = args[i + 1];
          i += 2;
          if (cmd == 'L') {
            cx = x;
            cy = y;
          } else {
            cx += x;
            cy += y;
          }
          path.lineTo(cx, cy);
        }
        break;
      case 'H':
      case 'h':
        while (i < args.length) {
          final x = args[i];
          i += 1;
          cx = cmd == 'H' ? x : cx + x;
          path.lineTo(cx, cy);
        }
        break;
      case 'V':
      case 'v':
        while (i < args.length) {
          final y = args[i];
          i += 1;
          cy = cmd == 'V' ? y : cy + y;
          path.lineTo(cx, cy);
        }
        break;
      case 'A':
      case 'a':
        while (i + 6 < args.length) {
          final rx = args[i], ry = args[i + 1], rot = args[i + 2];
          final large = args[i + 3] != 0, sweep = args[i + 4] != 0;
          final x = args[i + 5], y = args[i + 6];
          i += 7;
          final ex = cmd == 'A' ? x : cx + x;
          final ey = cmd == 'A' ? y : cy + y;
          _arcTo(path, cx, cy, rx, ry, rot * math.pi / 180.0, large, sweep, ex,
              ey);
          cx = ex;
          cy = ey;
        }
        break;
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
        break;
    }
  }
  return path;
}

/// 椭圆弧转三次贝塞尔（SVG 端点参数 → 中心参数）。
void _arcTo(Path path, double x1, double y1, double rx, double ry, double phi,
    bool largeArc, bool sweep, double x2, double y2) {
  if (rx == 0 || ry == 0) {
    path.lineTo(x2, y2);
    return;
  }
  rx = rx.abs();
  ry = ry.abs();
  final cosPhi = math.cos(phi), sinPhi = math.sin(phi);
  final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  final x1p = cosPhi * dx + sinPhi * dy;
  final y1p = -sinPhi * dx + cosPhi * dy;
  var rx2 = rx * rx, ry2 = ry * ry;
  final x1p2 = x1p * x1p, y1p2 = y1p * y1p;
  final lambda = x1p2 / rx2 + y1p2 / ry2;
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
    rx2 = rx * rx;
    ry2 = ry * ry;
  }
  var num = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2;
  if (num < 0) num = 0;
  final den = rx2 * y1p2 + ry2 * x1p2;
  final coef =
      (largeArc != sweep ? 1.0 : -1.0) * math.sqrt(den == 0 ? 0 : num / den);
  final cxp = coef * (rx * y1p / ry);
  final cyp = coef * (-ry * x1p / rx);
  final ccx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2;
  final ccy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2;

  double vecAngle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    if (len == 0) return 0;
    var a = math.acos((dot / len).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  final ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
  final vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
  final theta1 = vecAngle(1, 0, ux, uy);
  var dTheta = vecAngle(ux, uy, vx, vy);
  if (!sweep && dTheta > 0) {
    dTheta -= 2 * math.pi;
  } else if (sweep && dTheta < 0) {
    dTheta += 2 * math.pi;
  }

  final segs = (dTheta.abs() / (math.pi / 2)).ceil().clamp(1, 1000);
  final dSeg = dTheta / segs;
  final k = 4.0 / 3.0 * math.tan(dSeg / 4);

  Offset point(double t) => Offset(
        ccx + rx * math.cos(t) * cosPhi - ry * math.sin(t) * sinPhi,
        ccy + rx * math.cos(t) * sinPhi + ry * math.sin(t) * cosPhi,
      );
  Offset deriv(double t) => Offset(
        -rx * math.sin(t) * cosPhi - ry * math.cos(t) * sinPhi,
        -rx * math.sin(t) * sinPhi + ry * math.cos(t) * cosPhi,
      );

  var t1 = theta1;
  for (var s = 0; s < segs; s++) {
    final t2 = t1 + dSeg;
    final p1 = point(t1) + deriv(t1) * k;
    final p2 = point(t2) - deriv(t2) * k;
    final pe = point(t2);
    path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, pe.dx, pe.dy);
    t1 = t2;
  }
}

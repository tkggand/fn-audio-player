import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 播放设备：雷达式发现 + 当前输出 + 可用设备 + 网络参数。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient.instance;
  final _pc = PlayerController.instance;

  late final AnimationController _radar;
  StreamSubscription<void>? _sub;

  List<DlnaRenderer> _renderers = const [];
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  bool _autoSwitch = true;
  bool _dualStream = false;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _sub = _pc.stateChanges.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _scan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _radar.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _scanning = true;
      _error = null;
    });
    try {
      final list = await _api.dlnaRenderers(refresh: true);
      if (!mounted) return;
      setState(() => _renderers = list);
      fnToast(context, '发现 ${list.length} 台设备',
          icon: Icons.wifi_tethering_rounded);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _scanning = false;
        });
      }
    }
  }

  Future<void> _cast(DlnaRenderer r) async {
    if (_pc.current == null) {
      fnToast(context, '请先播放一首歌', icon: Icons.info_outline_rounded);
      return;
    }
    try {
      await _pc.castTo(r);
      if (mounted) {
        setState(() {});
        fnToast(context, '已投放到 ${r.name}', icon: Icons.cast_rounded);
      }
    } catch (e) {
      if (mounted) fnToast(context, '投放失败：$e');
    }
  }

  Future<void> _local() async {
    await _pc.backToLocal();
    if (mounted) {
      setState(() {});
      fnToast(context, '已切回本机扬声器', icon: Icons.speaker_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = fnBpOf(context).isWide;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: FnSplitPage(
          head: wide
              ? FnPageHead(
                  eyebrow: 'DLNA · AIRPLAY',
                  title: '播放设备',
                  subtitle: '${_renderers.length} 台可投放设备',
                  actions: [
                    FnIconBtn(
                      icon: Icons.refresh_rounded,
                      onTap: _loading ? null : _scan,
                    ),
                  ],
                )
              : FnNav(
                  title: '播放设备',
                  subtitle: 'DLNA · AIRPLAY',
                  trailing: [
                    FnIconBtn(
                      icon: Icons.refresh_rounded,
                      variant: FnIconBtnVariant.plain,
                      onTap: _loading ? null : _scan,
                    ),
                  ],
                ),
          left: [
            _radarCard(),
            const FnSectionHead(title: '当前输出', sub: 'ACTIVE'),
            _currentCard(),
            FnSectionHead(
              title: '可用设备',
              sub: '${_renderers.length} DEVICES',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              FnEmpty(
                icon: CupertinoIcons.exclamationmark_circle,
                title: '设备扫描失败',
                message: _error,
                actionLabel: '重试',
                onAction: _scan,
                compact: true,
              )
            else
              FnGroupCard(children: [
                _deviceRow(
                  icon: Icons.speaker_rounded,
                  name: '本机扬声器',
                  sub: '内置音频输出 · 48 kHz',
                  active: !_pc.isCasting,
                  online: true,
                  onTap: _pc.isCasting ? _local : null,
                ),
                for (final r in _renderers)
                  _deviceRow(
                    icon: Icons.tv_rounded,
                    name: r.name,
                    sub: r.location,
                    active: _pc.dlnaRenderer?.id == r.id,
                    online: true,
                    onTap: () => _cast(r),
                  ),
                if (_renderers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                    child: Text(
                      '没有发现可用的 DLNA 渲染器，确认设备与手机在同一局域网。',
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: FnColors.textTertiary),
                    ),
                  ),
              ]),
          ],
          right: [
            const FnGroupLabel('网络'),
            FnGroupCard(children: [
              FnListRow(
                icon: Icons.wifi_rounded,
                title: '局域网',
                subtitle: _api.baseUrl,
                value: '已连接',
                valueColor: FnColors.green,
                showChevron: false,
              ),
              const FnListRow(
                icon: Icons.settings_input_antenna_rounded,
                title: '传输协议',
                subtitle: 'DLNA 1.0 / AirPlay 2 / Cast',
                value: '自动',
                showChevron: false,
              ),
              FnListRow(
                icon: Icons.cast_connected_rounded,
                title: '自动切换设备',
                subtitle: '进入新网络时自动重连上次设备',
                showChevron: false,
                trailing: FnSwitch(
                  value: _autoSwitch,
                  onChanged: (v) => setState(() => _autoSwitch = v),
                ),
              ),
              FnListRow(
                icon: Icons.radio_rounded,
                title: '投放时保持本机播放',
                subtitle: '双流同步 · 会有轻微延迟',
                showChevron: false,
                trailing: FnSwitch(
                  value: _dualStream,
                  onChanged: (v) => setState(() => _dualStream = v),
                ),
              ),
            ]),
            Padding(
              padding: EdgeInsets.fromLTRB(fnPagePad(context), 14, fnPagePad(context), 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: FnColors.textTertiary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '设备列表来自 SSDP / mDNS 广播。投放后由 NAS 直接推送音频流，本机暂停播放。',
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.55,
                          color: FnColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
            FnPageFoot(
              left: 'SSDP · M-SEARCH',
              right: '网络设置',
              onRight: () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radarCard() {
    final online = _renderers.length + 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: AnimatedBuilder(
              animation: _radar,
              builder: (context, _) => CustomPaint(
                painter: _RadarPainter(
                  sweep: _radar.value,
                  scanning: _scanning,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DISCOVERY',
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.limeText,
                    )),
                const SizedBox(height: 4),
                Text(
                  _scanning ? '正在扫描局域网…' : '局域网内自动发现',
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  _scanning
                      ? 'SSDP M-SEARCH · 等待设备响应'
                      : '已发现 $online 台在线设备 · 每 30 秒刷新一次',
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.5,
                      color: FnColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _scanning ? FnColors.gold : FnColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _scanning ? 'SCANNING' : 'ONLINE',
                      style: TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                        fontFamily: FnText.monoFamily.first,
                        color: _scanning ? FnColors.gold : FnColors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentCard() {
    final song = _pc.current;
    final renderer = _pc.dlnaRenderer;
    final hue = song == null ? 190 : fnHue(song.id);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kFnPad),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), 0.6, 0.42)
                .toColor()
                .withValues(alpha: 0.30),
            FnColors.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: FnColors.glassLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                    renderer != null
                        ? Icons.tv_rounded
                        : Icons.speaker_rounded,
                    size: 20,
                    color: FnColors.limeText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(renderer?.name ?? '本机扬声器',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(renderer?.location ?? '内置音频输出 · 跟随源采样率',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: FnColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: FnColors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: FnColors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text('LIVE',
                        style: TextStyle(
                            fontSize: 9,
                            fontFamily: FnText.monoFamily.first,
                            color: FnColors.green)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: FnColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    song == null ? '未在播放' : '${song.title} · ${song.artist}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: FnColors.textSecondary),
                  ),
                ),
                if (song != null)
                  Text(
                    song.codec?.toUpperCase() ?? fmtSampleRate(song.sampleRate),
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.textTertiary,
                    ),
                  ),
                const SizedBox(width: 10),
                if (renderer != null)
                  FnButton(
                    label: '停止投放',
                    variant: FnButtonVariant.soft,
                    size: FnButtonSize.sm,
                    onTap: _local,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceRow({
    required IconData icon,
    required String name,
    required String sub,
    required bool active,
    required bool online,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active ? FnColors.limeSoft : FnColors.glassLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18,
                  color: active ? FnColors.lime : FnColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w500)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: FnColors.textSecondary)),
                ],
              ),
            ),
            Text(
              active ? 'ACTIVE' : online ? '可用' : '离线',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                fontFamily: FnText.monoFamily.first,
                color: active
                    ? FnColors.lime
                    : online
                        ? FnColors.textTertiary
                        : FnColors.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.sweep, required this.scanning});

  final double sweep;
  final bool scanning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final f in const [0.34, 0.62, 0.92]) {
      ring.color = FnColors.line;
      canvas.drawCircle(center, radius * f, ring);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          FnColors.lime.withValues(alpha: 0.20),
          FnColors.lime.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * 0.92, glow);

    final angle = sweep * math.pi * 2;
    final rect = Rect.fromCircle(center: center, radius: radius * 0.92);
    final cone = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          FnColors.lime.withValues(alpha: 0.0),
          FnColors.lime.withValues(alpha: 0.32),
          FnColors.lime.withValues(alpha: 0.0),
        ],
        stops: const [0, 0.12, 0.3],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.92, cone);

    final core = Paint()..color = FnColors.lime;
    canvas.drawCircle(center, 3, core);

    for (final p in const [Offset(-0.42, -0.28), Offset(0.36, 0.30), Offset(-0.16, 0.52)]) {
      final node = center + Offset(p.dx * radius, p.dy * radius);
      canvas.drawCircle(
          node,
          4,
          Paint()
            ..color = FnColors.lime.withValues(alpha: scanning ? 0.9 : 0.55));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweep != sweep || old.scanning != scanning;
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 扫描曲库：进度环 + 扫描目录 + 本次结果 + 选项 + 实时日志。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  static const _autoKey = 'fn_scan_auto';
  static const _hiddenKey = 'fn_scan_hidden';
  static const _shortKey = 'fn_scan_short';
  static const _coverKey = 'fn_scan_cover';
  static const _pruneKey = 'fn_scan_prune';

  final _api = ApiClient.instance;

  bool _loading = true;
  String? _error;
  ScanStatus? _status;
  List<ScanRoot> _roots = const [];
  Timer? _poll;

  bool _auto = true;
  bool _hidden = false;
  bool _short = true;
  bool _cover = true;
  bool _prune = true;

  final List<_LogLine> _log = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    _auto = prefs.getBool(_autoKey) ?? true;
    _hidden = prefs.getBool(_hiddenKey) ?? false;
    _short = prefs.getBool(_shortKey) ?? true;
    _cover = prefs.getBool(_coverKey) ?? true;
    _prune = prefs.getBool(_pruneKey) ?? true;
    try {
      final res = await Future.wait<Object>([
        _api.scanStatus(),
        _api.listScanRoots(),
      ]);
      if (!mounted) return;
      final status = res[0] as ScanStatus;
      setState(() {
        _status = status;
        _roots = res[1] as List<ScanRoot>;
        _loading = false;
      });
      if (_log.isEmpty) {
        _write('索引就绪 · 上次扫描 ${status.lastScanAt ?? '未知'}', _LogKind.dim);
        _write('已在 ${_roots.length} 个目录中建立索引', _LogKind.dim);
      }
      if (status.running) _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _write(String text, [_LogKind kind = _LogKind.normal]) {
    final now = DateTime.now();
    final stamp = [now.hour, now.minute, now.second]
        .map((n) => n.toString().padLeft(2, '0'))
        .join(':');
    setState(() => _log.add(_LogLine(stamp, text, kind)));
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      try {
        final s = await _api.scanStatus();
        if (!mounted) return;
        final wasRunning = _status?.running ?? false;
        setState(() => _status = s);
        if (wasRunning && !s.running) {
          _poll?.cancel();
          _write(
              '扫描完成 · 新增 ${s.last?.added ?? 0} / 更新 ${s.last?.updated ?? 0} / 移除 ${s.last?.removed ?? 0}',
              _LogKind.ok);
          fnToast(context, '曲库索引已更新', icon: Icons.check_rounded);
        }
      } catch (_) {
        // 轮询失败静默：下次继续。
      }
    });
  }

  Future<void> _start({bool force = false}) async {
    if (_status?.running == true) return;
    try {
      final s = await _api.rescan(force: force);
      if (!mounted) return;
      setState(() => _status = s);
      _write(force ? '重建索引 · 全量扫描已开始' : '开始扫描 · ${_roots.length} 个目录',
          force ? _LogKind.warn : _LogKind.dim);
      _startPolling();
      fnToast(context, force ? '已开始重建索引' : '已开始扫描',
          icon: Icons.refresh_rounded);
    } catch (e) {
      if (mounted) fnToast(context, '启动失败：$e');
    }
  }

  Future<void> _addRoot() async {
    final ctrl = TextEditingController(text: '/volume/music');
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('添加扫描目录', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: FnColors.textPrimary),
          decoration: const InputDecoration(hintText: '/volume/music'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    try {
      final root = await _api.addScanRoot(path);
      if (!mounted) return;
      setState(() => _roots = [..._roots, root]);
      _write('已添加目录 $path', _LogKind.dim);
      fnToast(context, '已添加扫描目录');
    } catch (e) {
      if (mounted) fnToast(context, '添加失败：$e');
    }
  }

  Future<void> _deleteRoot(ScanRoot root) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('移除目录？', style: TextStyle(fontSize: 17)),
        content: Text('索引中的曲目不会被删除，仅停止扫描该目录。',
            style: TextStyle(fontSize: 13, color: FnColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('移除', style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteScanRoot(root.id);
      if (!mounted) return;
      setState(() => _roots = _roots.where((r) => r.id != root.id).toList());
      _write('已移除目录 ${root.path}', _LogKind.err);
    } catch (e) {
      if (mounted) fnToast(context, '移除失败：$e');
    }
  }

  Future<void> _saveBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _settingsSheet() async {
    await showFnSheet<void>(
      context,
      eyebrow: 'SCAN',
      title: '扫描设置',
      children: [
        FnOptionRow(
          title: '索引设置',
          icon: Icons.settings_rounded,
          onTap: () {
            Navigator.pop(context);
            context.push('/settings');
          },
        ),
        FnOptionRow(
          title: '重建索引',
          subtitle: '清空后重新扫描全部目录',
          icon: Icons.restart_alt_rounded,
          danger: true,
          onTap: () {
            Navigator.pop(context);
            _start(force: true);
          },
        ),
        FnOptionRow(
          title: '清空日志',
          icon: CupertinoIcons.trash,
          onTap: () {
            Navigator.pop(context);
            setState(() => _log.clear());
            _write('日志已清空', _LogKind.dim);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const dp = fnDarkPalette;
    final wide = fnBpOf(context).isWide;
    final logSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FnSectionHead(
          title: '日志',
          sub: 'LIVE',
          actionLabel: '清空',
          onAction: () {
            setState(() => _log.clear());
            _write('日志已清空', _LogKind.dim);
          },
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: kFnPad),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 120),
          decoration: const BoxDecoration(
            color: Color(0xFF090A0C),
            borderRadius: BorderRadius.all(Radius.circular(16)),
            border: Border.fromBorderSide(BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in _log)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.time,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontFamily: FnText.monoFamily.first,
                            color: dp.textFaint,
                          )),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(line.text,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.5,
                              fontFamily: FnText.monoFamily.first,
                              color: switch (line.kind) {
                                _LogKind.ok => dp.lime,
                                _LogKind.warn => dp.gold,
                                _LogKind.err => dp.coral,
                                _LogKind.dim => dp.textTertiary,
                                _LogKind.normal => dp.textSecondary,
                              },
                            )),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Center(
                    child: FnEmpty(
                      icon: CupertinoIcons.exclamationmark_circle,
                      title: '扫描状态读取失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : FnSplitPage(
                    head: wide
                        ? FnPageHead(
                            eyebrow: 'LIBRARY SCAN',
                            title: '扫描曲库',
                            subtitle: '${_roots.length} 个目录 · 元数据 MusicBrainz',
                            actions: [
                              FnIconBtn(
                                icon: Icons.settings_rounded,
                                onTap: _settingsSheet,
                              ),
                            ],
                          )
                        : FnNav(
                            title: '扫描曲库',
                            subtitle: 'LIBRARY SCAN',
                            trailing: [
                              FnIconBtn(
                                icon: Icons.settings_rounded,
                                variant: FnIconBtnVariant.plain,
                                onTap: _settingsSheet,
                              ),
                            ],
                          ),
                    left: [
                      _hero(),
                      FnSectionHead(
                        title: '扫描目录',
                        sub: '${_roots.length} ROOTS',
                        actionLabel: '添加',
                        onAction: _addRoot,
                      ),
                      FnGroupCard(children: [
                        if (_roots.isEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(14, 6, 14, 16),
                            child: Text('还没有扫描目录，点击右上角「添加」。',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: FnColors.textTertiary)),
                          )
                        else
                          for (final r in _roots) _rootRow(r),
                      ]),
                      const FnSectionHead(title: '本次结果', sub: 'RESULT'),
                      _stats(),
                      const FnGroupLabel('扫描选项'),
                      FnGroupCard(children: [
                        FnListRow(
                          icon: CupertinoIcons.clock,
                          title: '每日自动扫描',
                          subtitle: '每天 02:00 · 仅 Wi-Fi',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _auto,
                            onChanged: (v) async {
                              setState(() => _auto = v);
                              await _saveBool(_autoKey, v);
                            },
                          ),
                        ),
                        FnListRow(
                          icon: CupertinoIcons.folder,
                          title: '扫描隐藏文件',
                          subtitle: '包含 . 开头的目录',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _hidden,
                            onChanged: (v) async {
                              setState(() => _hidden = v);
                              await _saveBool(_hiddenKey, v);
                            },
                          ),
                        ),
                        FnListRow(
                          icon: CupertinoIcons.timer,
                          title: '忽略短音频',
                          subtitle: '时长小于 30 秒的文件',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _short,
                            onChanged: (v) async {
                              setState(() => _short = v);
                              await _saveBool(_shortKey, v);
                            },
                          ),
                        ),
                        FnListRow(
                          icon: CupertinoIcons.photo,
                          title: '读取内嵌封面',
                          subtitle: '优先使用音频内嵌图片',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _cover,
                            onChanged: (v) async {
                              setState(() => _cover = v);
                              await _saveBool(_coverKey, v);
                            },
                          ),
                        ),
                        FnListRow(
                          icon: CupertinoIcons.trash,
                          title: '清理失效条目',
                          subtitle: '移除文件已不存在的记录',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _prune,
                            onChanged: (v) async {
                              setState(() => _prune = v);
                              await _saveBool(_pruneKey, v);
                            },
                          ),
                        ),
                      ]),
                    ],
                    right: [
                      logSection,
                      FnPageFoot(
                        left: 'METADATA · MUSICBRAINZ',
                        right: '索引设置',
                        onRight: () => context.push('/settings'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _rootRow(ScanRoot r) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _deleteRoot(r),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: FnColors.glassLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(CupertinoIcons.folder,
                  size: 17, color: FnColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w500)),
                  Text('本地 · ${r.enabled ? '可读写' : '已停用'}',
                      style: TextStyle(
                          fontSize: 10.5, color: FnColors.textSecondary)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _deleteRoot(r),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(CupertinoIcons.minus_circle,
                    size: 17, color: FnColors.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    final running = _status?.running ?? false;
    final pct = (_status?.progress ?? 0).clamp(0, 100);
    final last = _status?.last;
    final summary = last == null
        ? '还没有扫描记录，先添加目录再开始扫描。'
        : '上次扫描共 ${last.scanned} 个文件，新增 ${last.added} 首、更新 ${last.updated} 首、移除 ${last.removed} 首。';
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
            width: 104,
            height: 104,
            child: CustomPaint(
              painter: _ScanRingPainter(
                pct: pct / 100,
                running: running,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$pct%',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: running ? FnColors.lime : FnColors.textPrimary,
                        )),
                    const SizedBox(height: 1),
                    Text(running ? '扫描中' : (pct >= 100 ? '完成' : '待扫描'),
                        style: TextStyle(
                            fontSize: 9.5, color: FnColors.textTertiary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST SCAN',
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.textTertiary,
                    )),
                const SizedBox(height: 3),
                Text(_status?.lastScanAt ?? '从未扫描',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(summary,
                    style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: FnColors.textSecondary)),
                const SizedBox(height: 10),
                FnButton(
                  label: running
                      ? '扫描中…'
                      : (last == null ? '开始扫描' : '重新扫描'),
                  icon: Icons.refresh_rounded,
                  size: FnButtonSize.sm,
                  enabled: !running,
                  onTap: () => _start(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final last = _status?.last;
    Widget tile(String value, String label, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
          decoration: BoxDecoration(
            color: FnColors.surface,
            borderRadius: BorderRadius.circular(FnRadius.sm),
            border: Border.all(color: FnColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style:
                      TextStyle(fontSize: 10, color: FnColors.textTertiary)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 4),
      child: Row(
        children: [
          tile('${last?.added ?? 0}', '新增曲目', FnColors.lime),
          const SizedBox(width: 8),
          tile('${last?.updated ?? 0}', '更新元数据', FnColors.cyan),
          const SizedBox(width: 8),
          tile('${last?.removed ?? 0}', '移除失效', FnColors.coral),
        ],
      ),
    );
  }
}

enum _LogKind { normal, dim, ok, warn, err }

class _LogLine {
  _LogLine(this.time, this.text, this.kind);
  final String time;
  final String text;
  final _LogKind kind;
}

class _ScanRingPainter extends CustomPainter {
  _ScanRingPainter({required this.pct, required this.running});

  final double pct;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = FnColors.surface3;
    canvas.drawCircle(center, radius, base);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: [FnColors.lime.withValues(alpha: 0.55), FnColors.lime],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    if (pct <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * pct.clamp(0.0, 1.0),
      false,
      arc,
    );

    if (running) {
      canvas.drawCircle(
          center,
          2.5,
          Paint()
            ..color = FnColors.lime.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(_ScanRingPainter old) =>
      old.pct != pct || old.running != running;
}

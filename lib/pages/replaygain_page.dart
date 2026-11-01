import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 响度均衡（ReplayGain）：模式 / 目标响度 / 标签覆盖 / 测量 / 当前曲目增益。
class ReplayGainPage extends StatefulWidget {
  const ReplayGainPage({super.key});

  @override
  State<ReplayGainPage> createState() => _ReplayGainPageState();
}

class _ReplayGainPageState extends State<ReplayGainPage> {
  static const _targetKey = 'fn_rg_target';
  static const _preventKey = 'fn_rg_prevent_clip';
  static const _fallbackKey = 'fn_rg_fallback';

  final _api = ApiClient.instance;
  final _pc = PlayerController.instance;

  ReplayGainStatus? _status;
  List<Song> _tracks = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  double _target = -18;
  bool _preventClip = true;
  bool _fallback = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    _target = (prefs.getDouble(_targetKey) ?? -18).clamp(-23, -9);
    _preventClip = prefs.getBool(_preventKey) ?? true;
    _fallback = prefs.getBool(_fallbackKey) ?? true;
    try {
      final status = await _api.getReplayGainStatus();
      final songs = _pc.queue.isNotEmpty
          ? _pc.queue.take(8).toList()
          : (await _api.fetchSongs()).take(8).toList();
      if (!mounted) return;
      setState(() {
        _status = status;
        _tracks = songs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setMode(String mode) async {
    await _pc.setRgMode(mode);
    if (mounted) {
      setState(() {});
      fnToast(
        context,
        switch (mode) {
          'off' => '已关闭响度均衡',
          'track' => '已切换为曲目增益',
          _ => '已切换为专辑增益',
        },
        icon: Icons.volume_up_rounded,
      );
    }
  }

  Future<void> _saveTarget(double v) async {
    setState(() => _target = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_targetKey, v);
  }

  Future<void> _toggle(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
    setState(() {
      if (key == _preventKey) _preventClip = v;
      if (key == _fallbackKey) _fallback = v;
    });
  }

  Future<void> _analyze({bool all = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await _api.analyzeReplayGainBatch(
        scope: all ? 'all' : 'missing',
        force: all,
        limit: all ? null : 200,
      );
      await _load();
      if (mounted) {
        fnToast(
          context,
          '测量完成 · 成功 ${s.measured} 首，跳过 ${s.skipped} 首，失败 ${s.failed} 首',
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (mounted) fnToast(context, '测量失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _ratio(int n) {
    final total = _status?.total ?? 0;
    if (total <= 0) return 0;
    return (n / total).clamp(0.0, 1.0);
  }

  String _gainText(Song s) {
    final g = _pc.rgMode == 'album' ? s.rgAlbumGain : s.rgTrackGain;
    if (g == null) return '未标记';
    final sign = g >= 0 ? '+' : '−';
    return 'RG $sign${g.abs().toStringAsFixed(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final wide = fnBpOf(context).isWide;
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
                      title: '读取 ReplayGain 状态失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : FnSplitPage(
                    head: wide
                        ? FnPageHead(
                            eyebrow: 'REPLAYGAIN',
                            title: '响度均衡',
                            subtitle: '按标签统一响度 · EBU R128',
                            actions: [
                              FnIconBtn(
                                icon: Icons.refresh_rounded,
                                onTap: _load,
                              ),
                            ],
                          )
                        : FnNav(
                            title: '响度均衡',
                            subtitle: 'REPLAYGAIN',
                            trailing: [
                              FnIconBtn(
                                icon: Icons.refresh_rounded,
                                variant: FnIconBtnVariant.plain,
                                onTap: _load,
                              ),
                            ],
                          ),
                    left: [
                      _banner(),
                      const FnGroupLabel('模式'),
                      FnGroupCard(children: [
                        _modeRow('off', '关闭', '按原始电平播放',
                            Icons.volume_off_rounded),
                        _modeRow('track', '曲目增益', '每首歌统一到同一响度',
                            Icons.music_note_rounded),
                        _modeRow('album', '专辑增益', '保留专辑内动态关系',
                            Icons.album_rounded),
                      ]),
                      const FnGroupLabel('参数'),
                      FnGroupCard(children: [
                        _targetSlider(),
                        FnListRow(
                          icon: Icons.graphic_eq_rounded,
                          title: '防止削波',
                          subtitle: '峰值超过 0 dBFS 时自动限制',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _preventClip,
                            onChanged: (v) => _toggle(_preventKey, v),
                          ),
                        ),
                        FnListRow(
                          icon: Icons.hearing_rounded,
                          title: '无标签时使用回退增益',
                          subtitle: '回退值 −6.0 dB',
                          showChevron: false,
                          trailing: FnSwitch(
                            value: _fallback,
                            onChanged: (v) => _toggle(_fallbackKey, v),
                          ),
                        ),
                      ]),
                    ],
                    right: [
                      FnSectionHead(
                        title: '标签覆盖',
                        sub: 'LIBRARY-WIDE',
                        actionLabel: _busy ? '测量中…' : '开始测量',
                        onAction: _busy ? null : () => _analyze(),
                      ),
                      _stats(),
                      _progressCard(),
                      const FnSectionHead(title: '当前播放', sub: 'PER-TRACK'),
                      if (_tracks.isEmpty)
                        const FnEmpty(
                          icon: CupertinoIcons.music_note,
                          title: '还没有曲目',
                          compact: true,
                        )
                      else
                        for (var i = 0; i < _tracks.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: kFnPad - 8),
                            child: FnSongRow(
                              song: _tracks[i],
                              showDuration: false,
                              subtitle:
                                  '${_tracks[i].artist} · ${_tracks[i].album}',
                              trailing: Text(
                                _gainText(_tracks[i]),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontFamily: FnText.monoFamily.first,
                                  color: _tracks[i].rgTrackGain == null
                                      ? FnColors.textFaint
                                      : (_tracks[i].rgTrackGain!.abs() > 7.5
                                          ? FnColors.coral
                                          : FnColors.lime),
                                ),
                              ),
                              isCurrent: _pc.current?.id == _tracks[i].id,
                              isPlaying: _pc.isPlaying,
                              onTap: () {
                                _pc.playList(_tracks, i);
                              },
                            ),
                          ),
                      FnPageFoot(
                        left: 'REPLAYGAIN 2.0 · TAG BASED',
                        right: '返回调音',
                        onRight: () => context.push('/tuning'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FnColors.limeSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.volume_up_rounded,
                size: 20, color: FnColors.limeText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('让每一首一样响',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(
                  '读取曲目内的 ReplayGain 标签，在解码阶段按目标响度调整增益，不改变原始文件。未标记的曲目会回退到统一增益。',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: FnColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeRow(String mode, String title, String sub, IconData icon) {
    final on = _pc.rgMode == mode;
    return FnListRow(
      icon: icon,
      iconColor: on ? FnColors.lime : null,
      title: title,
      subtitle: sub,
      showChevron: false,
      onTap: () => _setMode(mode),
      trailing: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? FnColors.lime : Colors.transparent,
          border: Border.all(
              color: on ? FnColors.lime : FnColors.line2, width: 1.4),
        ),
        child: on
            ? Icon(Icons.check_rounded, size: 12, color: FnColors.limeInk)
            : null,
      ),
    );
  }

  Widget _targetSlider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              Text('目标响度',
                  style: TextStyle(
                      fontSize: 14.5, color: FnColors.textPrimary)),
              const Spacer(),
              Text('−${_target.abs().toStringAsFixed(0)} LUFS',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.limeText)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: FnColors.lime,
              inactiveTrackColor: FnColors.line2,
              thumbColor: FnColors.lime,
              overlayColor: FnColors.lime.withValues(alpha: 0.14),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              min: -23,
              max: -9,
              divisions: 14,
              value: _target,
              onChanged: (v) => setState(() => _target = v),
              onChangeEnd: _saveTarget,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('按 EBU R128 / ITU-R BS.1770-4 测量',
                style:
                    TextStyle(fontSize: 10, color: FnColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final s = _status;
    Widget tile(String value, String label, int n, Color color) {
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
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: color)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: FnColors.textTertiary)),
              const SizedBox(height: 7),
              FnProgressBar(value: _ratio(n), height: 3, color: color),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 6),
      child: Row(
        children: [
          tile(s == null ? '—' : '${s.analyzed}', '已测量', s?.analyzed ?? 0,
              FnColors.lime),
          const SizedBox(width: 8),
          tile(s == null ? '—' : '${s.tagged}', '标签读取', s?.tagged ?? 0,
              FnColors.cyan),
          const SizedBox(width: 8),
          tile(s == null ? '—' : '${s.pending}', '待处理', s?.pending ?? 0,
              FnColors.gold),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final s = _status;
    final total = s?.total ?? 0;
    final done = (s?.analyzed ?? 0) + (s?.tagged ?? 0);
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 6, kFnPad, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.md),
        border: Border.all(color: FnColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('扫描进度',
                  style:
                      TextStyle(fontSize: 12, color: FnColors.textSecondary)),
              const Spacer(),
              Text(_busy ? '测量中…' : (s?.pending ?? 0) == 0 ? '完成' : '尚未完成',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _busy ? FnColors.gold : FnColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 9),
          FnProgressBar(
            value: pct,
            height: 5,
            color: FnColors.lime,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _busy
                      ? '正在分析未标记曲目…'
                      : '已覆盖 $done / $total 首曲目',
                  style:
                      TextStyle(fontSize: 10, color: FnColors.textTertiary),
                ),
              ),
              Text('EBU R128',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: FnText.monoFamily.first,
                    color: FnColors.textTertiary,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

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

/// 调音：DSP 预设 / 10 段均衡器（曲线 + 推子）/ AutoEq / 空间与淡入淡出 / 电平。
class TuningPage extends StatefulWidget {
  const TuningPage({super.key});

  @override
  State<TuningPage> createState() => _TuningPageState();
}

class _TuningPageState extends State<TuningPage> {
  static const _freqs = <double>[
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  static const _cfKey = 'fn_dsp_crossfeed';
  static const _widthKey = 'fn_dsp_width';
  static const _fadeInKey = 'fn_dsp_fade_in';
  static const _fadeOutKey = 'fn_dsp_fade_out';
  static const _autoEqKey = 'fn_dsp_autoeq';
  static const _headroomKey = 'fn_dsp_headroom';
  static const _fadeKey = 'fn_dsp_fade';

  final _api = ApiClient.instance;
  final _pc = PlayerController.instance;

  bool _loading = true;
  String? _error;
  bool _busy = false;

  List<DspPreset> _presets = const [];
  EqState? _eq;
  final List<double> _gains = List<double>.filled(10, 0);
  int _activeBand = 0;
  int _mode = 0; // 0 = 10 段可编辑，1 = 31 段只读预览

  bool _autoEq = true;
  bool _headroom = true;
  bool _fade = true;
  double _crossfeed = 28;
  double _width = 10; // 0-20 → 0.0-2.0×

  double _fadeIn = 800;
  double _fadeOut = 1500;

  Timer? _meter;
  double _meterL = 0.52;
  double _meterR = 0.46;

  bool get _eqDirty => _eq?.profile.enabled != true;

  @override
  void initState() {
    super.initState();
    _load();
    _meter = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      if (!_pc.isPlaying) {
        if (_meterL != 0 || _meterR != 0) {
          setState(() {
            _meterL = 0;
            _meterR = 0;
          });
        }
        return;
      }
      final rnd = math.Random();
      setState(() {
        _meterL = 0.42 + rnd.nextDouble() * 0.38;
        _meterR = 0.38 + rnd.nextDouble() * 0.40;
      });
    });
  }

  @override
  void dispose() {
    _meter?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    _autoEq = prefs.getBool(_autoEqKey) ?? true;
    _headroom = prefs.getBool(_headroomKey) ?? true;
    _fade = prefs.getBool(_fadeKey) ?? true;
    _crossfeed = (prefs.getDouble(_cfKey) ?? 28).clamp(0, 100);
    _width = (prefs.getDouble(_widthKey) ?? 10).clamp(0, 20);
    _fadeIn = (prefs.getDouble(_fadeInKey) ?? 800).clamp(0, 3000);
    _fadeOut = (prefs.getDouble(_fadeOutKey) ?? 1500).clamp(0, 3000);
    try {
      final res = await Future.wait<Object>([
        _api.fetchDspPresets(),
        _api.getEq(),
      ]);
      final presets = res[0] as List<DspPreset>;
      final eq = res[1] as EqState;
      if (!mounted) return;
      // 本地缓存的预设 id 已失效时先校准回直通，再渲染选中态。
      await _pc.reconcilePreset(presets);
      setState(() {
        _presets = presets;
        _eq = eq;
        _syncBands(eq);
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

  void _syncBands(EqState eq) {
    for (var i = 0; i < _gains.length; i++) {
      _gains[i] = 0;
    }
    final bands = eq.profile.bands;
    if (bands.isEmpty) return;
    for (var i = 0; i < _freqs.length; i++) {
      var best = bands.first;
      var bestDist = double.infinity;
      for (final b in bands) {
        final d = (b.freq - _freqs[i]).abs();
        if (d < bestDist) {
          bestDist = d;
          best = b;
        }
      }
      _gains[i] = best.gain.clamp(-12.0, 12.0);
    }
  }

  String get _activeName {
    final pid = _pc.presetId;
    if (pid == null) {
      return _eq?.profile.enabled == true ? '自定义曲线' : '直通';
    }
    for (final p in _presets) {
      if (p.id == pid) return p.name;
    }
    return '预设 #$pid';
  }

  DspPreset? get _activePreset {
    final pid = _pc.presetId;
    for (final p in _presets) {
      if (p.id == pid) return p;
    }
    return null;
  }

  Future<void> _selectPreset(DspPreset p) async {
    try {
      await _pc.setPreset(p.id);
      if (!mounted) return;
      setState(() {});
      fnToast(context, '已切换到「${p.name}」', icon: Icons.tune_rounded);
    } catch (e) {
      if (mounted) fnToast(context, '切换失败：$e');
    }
  }

  Future<void> _reset() async {
    setState(() {
      for (var i = 0; i < _gains.length; i++) {
        _gains[i] = 0;
      }
      _activeBand = 0;
    });
    try {
      await _pc.setPreset(null);
      await _api.clearEq();
      await _load();
      if (mounted) {
        fnToast(context, '已重置为直通', icon: Icons.refresh_rounded);
      }
    } catch (e) {
      if (mounted) fnToast(context, '重置失败：$e');
    }
  }

  Future<void> _applyEq() async {
    setState(() => _busy = true);
    try {
      final profile = EqProfile(
        enabled: true,
        headroom: _headroom ? 'safe' : 'manual',
        bands: [
          for (var i = 0; i < _freqs.length; i++)
            EqBand(
              freq: _freqs[i],
              gain: _gains[i],
              q: 1.0,
              type: 'peak',
            ),
        ],
        source: 'manual',
      );
      final state = await _api.putEq(profile);
      await _pc.setPreset(_pc.presetId);
      if (!mounted) return;
      setState(() => _eq = state);
      fnToast(context, 'DSP 参数已应用', icon: Icons.check_rounded);
    } catch (e) {
      if (mounted) fnToast(context, '应用失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController(text: '我的调音');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('保存为预设', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FnColors.textPrimary),
          decoration: const InputDecoration(hintText: '预设名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      final detail = await _api.createDspPreset(
        name: name.trim(),
        description: '自定义曲线 · 10 段 EQ',
        camillaYaml: _buildYaml(),
      );
      final presets = await _api.fetchDspPresets();
      await _pc.setPreset(detail.id);
      if (!mounted) return;
      setState(() => _presets = presets);
      fnToast(context, '已保存预设「${name.trim()}」',
          icon: Icons.check_rounded);
    } catch (e) {
      if (mounted) fnToast(context, '保存失败：$e');
    }
  }

  String _buildYaml() {
    final b = StringBuffer('filters:\n');
    for (var i = 0; i < _freqs.length; i++) {
      b.writeln('  band$i:');
      b.writeln('    type: Biquad');
      b.writeln('    parameters:');
      b.writeln('      type: Peaking');
      b.writeln('      freq: ${_freqs[i].toStringAsFixed(0)}');
      b.writeln('      gain: ${_gains[i].toStringAsFixed(1)}');
      b.writeln('      q: 1.0');
    }
    final names = [
      for (var i = 0; i < _freqs.length; i++) 'band$i',
    ].join(', ');
    b.writeln('pipeline:');
    b.writeln('  - type: Filter');
    b.writeln('    channel: 0');
    b.writeln('    names: [$names]');
    b.writeln('  - type: Filter');
    b.writeln('    channel: 1');
    b.writeln('    names: [$names]');
    return b.toString();
  }

  Future<void> _persistDouble(String key, double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, v);
  }

  Future<void> _persistBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _pickTarget() async {
    const targets = [
      'Harman 2019 In-Ear',
      'IEF Neutral',
      'Diffuse Field',
      'Flat',
    ];
    await showFnSheet<void>(
      context,
      eyebrow: 'AUTOEQ',
      title: '目标曲线',
      children: [
        for (var i = 0; i < targets.length; i++)
          FnOptionRow(
            title: targets[i],
            icon: Icons.show_chart_rounded,
            on: i == 0,
            onTap: () {
              Navigator.pop(context);
              fnToast(context, '目标曲线：${targets[i]}',
                  icon: Icons.tune_rounded);
            },
          ),
      ],
    );
  }

  Future<void> _pickModel() async {
    const models = [
      'Sennheiser HD 600',
      'Apple AirPods Pro 2',
      'Moondrop Blessing 3',
      'Sony WH-1000XM5',
    ];
    await showFnSheet<void>(
      context,
      eyebrow: 'HEADPHONE',
      title: '耳机型号',
      subtitle: '匹配 AutoEq 测量数据',
      children: [
        for (var i = 0; i < models.length; i++)
          FnOptionRow(
            title: models[i],
            subtitle: i == 0 ? '已匹配' : 'AutoEq 数据库',
            icon: Icons.headphones_rounded,
            on: i == 0,
            onTap: () {
              Navigator.pop(context);
              fnToast(context, '已匹配 ${models[i]}');
            },
          ),
      ],
    );
  }

  double get _peak {
    final v = math.max(_meterL, _meterR);
    if (v <= 0) return -60;
    return 20 * math.log(v) / math.ln10;
  }

  @override
  Widget build(BuildContext context) {
    final wide = fnBpOf(context).isWide;

    final head = wide
        ? FnPageHead(
            eyebrow: 'DSP · EQ',
            title: '调音',
            subtitle: '实时处理链路 · 32-bit float',
            actions: [
              FnIconBtn(icon: Icons.refresh_rounded, onTap: _reset),
            ],
          )
        : FnNav(
            title: '调音',
            subtitle: 'DSP · EQ',
            trailing: [
              FnIconBtn(
                icon: Icons.refresh_rounded,
                variant: FnIconBtnVariant.plain,
                onTap: _reset,
              ),
            ],
          );

    final presetSection = Column(
      children: [
        FnSectionHead(
          title: '预设',
          sub: 'PRESETS',
          actionLabel: '保存当前',
          onAction: _savePreset,
        ),
        _presetRow(),
      ],
    );

    final autoEqSection = Column(
      children: [
        const FnGroupLabel('AutoEq 校正'),
        FnGroupCard(children: [
          FnListRow(
            icon: Icons.headphones_rounded,
            title: 'AutoEq 耳机校正',
            subtitle: '按目标曲线自动补偿频响',
            showChevron: false,
            trailing: FnSwitch(
              value: _autoEq,
              onChanged: (v) async {
                setState(() => _autoEq = v);
                await _persistBool(_autoEqKey, v);
                if (!context.mounted) return;
                fnToast(context, 'AutoEq 已${v ? '开启' : '关闭'}');
              },
            ),
          ),
          FnListRow(
            icon: Icons.tune_rounded,
            title: '目标曲线',
            subtitle: 'Harman 2019 In-Ear',
            value: '切换',
            onTap: _pickTarget,
          ),
          FnListRow(
            icon: Icons.graphic_eq_rounded,
            title: '耳机型号',
            subtitle: 'Sennheiser HD 600',
            value: '匹配',
            onTap: _pickModel,
          ),
        ]),
      ],
    );

    final spaceSection = Column(
      children: [
        const FnGroupLabel('空间与增益'),
        FnGroupCard(children: [
          _sliderRow(
            title: '交叉馈送',
            valueLabel: '${_crossfeed.round()}%',
            value: _crossfeed,
            min: 0,
            max: 100,
            divisions: 20,
            foot: '让耳机听感更接近音箱',
            onChanged: (v) => setState(() => _crossfeed = v),
            onEnd: (v) => _persistDouble(_cfKey, v),
          ),
          _sliderRow(
            title: '声场宽度',
            valueLabel: '${(_width / 10).toStringAsFixed(1)}×',
            value: _width,
            min: 0,
            max: 20,
            divisions: 20,
            foot: 'Mid / Side 比例调整',
            onChanged: (v) => setState(() => _width = v),
            onEnd: (v) => _persistDouble(_widthKey, v),
          ),
          FnListRow(
            icon: Icons.shield_rounded,
            title: 'Headroom 保护',
            subtitle: '自动衰减，避免削波',
            showChevron: false,
            trailing: FnSwitch(
              value: _headroom,
              onChanged: (v) async {
                setState(() => _headroom = v);
                await _persistBool(_headroomKey, v);
              },
            ),
          ),
        ]),
      ],
    );

    final fadeSection = Column(
      children: [
        const FnGroupLabel('淡入淡出'),
        FnGroupCard(children: [
          _sliderRow(
            title: '淡入',
            valueLabel: '${_fadeIn.round()} ms',
            value: _fadeIn,
            min: 0,
            max: 3000,
            divisions: 30,
            onChanged: (v) => setState(() => _fadeIn = v),
            onEnd: (v) => _persistDouble(_fadeInKey, v),
          ),
          _sliderRow(
            title: '淡出',
            valueLabel: '${_fadeOut.round()} ms',
            value: _fadeOut,
            min: 0,
            max: 3000,
            divisions: 30,
            onChanged: (v) => setState(() => _fadeOut = v),
            onEnd: (v) => _persistDouble(_fadeOutKey, v),
          ),
          FnListRow(
            icon: Icons.leak_add_rounded,
            title: '切换歌曲时淡入淡出',
            subtitle: '手动切歌与自动下一首均生效',
            showChevron: false,
            trailing: FnSwitch(
              value: _fade,
              onChanged: (v) async {
                setState(() => _fade = v);
                await _persistBool(_fadeKey, v);
              },
            ),
          ),
        ]),
      ],
    );

    final meterSection = Column(
      children: [
        FnSectionHead(
          title: '电平',
          sub: 'PEAK · ${_fmtDb(_peak)} dBFS',
        ),
        _meterCard(),
      ],
    );

    final actions = Padding(
      padding: EdgeInsets.fromLTRB(fnPagePad(context), 16, fnPagePad(context), 10),
      child: Column(
        children: [
          FnButton(
            label: _busy ? '应用中…' : '应用到当前播放',
            icon: Icons.check_rounded,
            block: true,
            enabled: !_busy,
            onTap: _applyEq,
          ),
          const SizedBox(height: 8),
          FnButton(
            label: 'ReplayGain 设置',
            icon: Icons.volume_up_rounded,
            variant: FnButtonVariant.soft,
            block: true,
            onTap: () => context.push('/replaygain'),
          ),
        ],
      ),
    );

    final foot = FnPageFoot(
      left: 'DSP ENGINE · 32-BIT FLOAT',
      right: '高级设置',
      onRight: () => context.push('/settings'),
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
                      title: '调音加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : wide
                    ? SizedBox(
                        width: double.infinity,
                        child: Center(
                          child: ConstrainedBox(
                            // design/v3 css/pages/tuning.css `[data-page="tuning"] .pbody`
                            // max-width: 1080px。
                            constraints: const BoxConstraints(maxWidth: 1080),
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              physics: const BouncingScrollPhysics(),
                              children: [
                                head,
                                _banner(),
                                presetSection,
                                _eqCard(),
                                // desktop：AutoEq / 电平双列，空间与淡入淡出通栏。
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: kFnPad),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: autoEqSection),
                                      const SizedBox(width: 16),
                                      Expanded(child: meterSection),
                                    ],
                                  ),
                                ),
                                spaceSection,
                                fadeSection,
                                actions,
                                foot,
                              ],
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding:
                            EdgeInsets.only(bottom: fnBottomGapOf(context)),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          head,
                          _banner(),
                          presetSection,
                          _eqCard(),
                          autoEqSection,
                          spaceSection,
                          fadeSection,
                          meterSection,
                          actions,
                          foot,
                        ],
                      ),
      ),
    );
  }

  String _fmtDb(double v) {
    if (v <= -59) return '−∞';
    return v.toStringAsFixed(1);
  }

  Widget _banner() {
    final preset = _activePreset;
    final name = _activeName;
    final desc = preset?.description ??
        (_eq?.profile.enabled == true
            ? '自定义曲线 · 10 段均衡'
            : '未做任何音色处理');
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: FnColors.limeSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.tune_rounded,
                size: 21, color: FnColors.limeText),
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
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: FnColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: FnColors.glassLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('DSP',
                style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    fontFamily: FnText.monoFamily.first,
                    color: FnColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _presetRow() {
    final pid = _pc.presetId;
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kFnPad),
        physics: const BouncingScrollPhysics(),
        children: [
          _presetChip(
            title: '直通',
            tag: 'SYSTEM',
            on: pid == null && _eq?.profile.enabled != true,
            onTap: () async {
              await _pc.setPreset(null);
              setState(() {});
            },
          ),
          _presetChip(
            title: '自定义',
            tag: _eqDirty ? 'MINE' : 'ACTIVE',
            on: _eq?.profile.enabled == true,
            onTap: () => fnToast(context, '当前均衡曲线',
                icon: Icons.tune_rounded),
          ),
          for (final p in _presets)
            _presetChip(
              title: p.name,
              tag: p.isSystem ? 'SYSTEM' : 'MINE',
              on: p.id == pid,
              onTap: p.id == pid ? null : () => _selectPreset(p),
            ),
        ],
      ),
    );
  }

  Widget _presetChip({
    required String title,
    required String tag,
    required bool on,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? FnColors.limeSoft : FnColors.surface,
          borderRadius: BorderRadius.circular(FnRadius.sm),
          border: Border.all(color: on ? FnColors.lime : FnColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: on ? FnColors.lime : FnColors.textPrimary)),
            const SizedBox(height: 2),
            Text(tag,
                style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 0.8,
                    fontFamily: FnText.monoFamily.first,
                    color:
                        on ? FnColors.lime.withValues(alpha: 0.7) : FnColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _eqCard() {
    final wide = fnBpOf(context).isWide;
    final curve = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 112,
          child: CustomPaint(
            painter: _EqCurvePainter(
              gains: _mode == 0 ? _gains : _interpolate31(),
              showDots: _mode == 0,
              activeBand: _mode == 0 ? _activeBand : -1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final f in (_mode == 0
                ? const ['31', '125', '1k', '8k', '16k']
                : const ['20 Hz', '100', '1 k', '10 k', '20 kHz']))
              Text(f,
                  style: TextStyle(
                      fontSize: 8.5,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.textTertiary)),
          ],
        ),
      ],
    );
    // design/v3 css/pages/tuning.css `.eq-stage`：laptop / desktop 双栏
    //（曲线 1fr + 推子 320px），mobile 单列上下堆叠。
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: curve),
              const SizedBox(width: 16),
              SizedBox(
                width: 320,
                child: _mode == 0
                    ? _bands()
                    : Text('31 段为只读频谱预览 · 切回 10 段可编辑推子',
                        style: TextStyle(
                            fontSize: 9.5, color: FnColors.textTertiary)),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              curve,
              if (_mode == 0) ...[
                const SizedBox(height: 10),
                _bands(),
              ],
            ],
          );
    return Container(
      // laptop / desktop 页身限宽 1080（design/v3 css/pages/tuning.css）。
      margin: const EdgeInsets.fromLTRB(kFnPad, 14, kFnPad, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EQUALIZER',
                      style: TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 1.2,
                        fontFamily: FnText.monoFamily.first,
                        color: FnColors.textTertiary,
                      )),
                  const SizedBox(height: 2),
                  Text(_mode == 0 ? '10 段均衡器' : '31 段频谱',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              const Spacer(),
              FnSegmented(
                labels: const ['10 段', '31 段'],
                index: _mode,
                onChanged: (i) => setState(() => _mode = i),
                lime: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _mode == 0
                    ? '${_bandLabel(_activeBand)} · ${_fmtGain(_gains[_activeBand])}'
                    : '31 段',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.limeText,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _mode == 0 ? '拖动推子调整增益' : '只读频谱预览 · 切回 10 段可编辑',
                style:
                    TextStyle(fontSize: 9.5, color: FnColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  List<double> _interpolate31() {
    final out = <double>[];
    for (var i = 0; i < 31; i++) {
      final t = i / 30 * (_gains.length - 1);
      final lo = t.floor();
      final hi = math.min(lo + 1, _gains.length - 1);
      final f = t - lo;
      out.add(_gains[lo] * (1 - f) + _gains[hi] * f);
    }
    return out;
  }

  Widget _bands() {
    return SizedBox(
      height: 108,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _gains.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => setState(() => _activeBand = i),
                child: Column(
                  children: [
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            activeTrackColor: FnColors.lime,
                            inactiveTrackColor: FnColors.line2,
                            thumbColor:
                                i == _activeBand ? FnColors.lime : FnColors.textSecondary,
                            overlayColor:
                                FnColors.lime.withValues(alpha: 0.12),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5),
                            overlayShape: SliderComponentShape.noOverlay,
                          ),
                          child: Slider(
                            min: -12,
                            max: 12,
                            divisions: 48,
                            value: _gains[i].clamp(-12, 12),
                            onChanged: (v) => setState(() {
                              _gains[i] = v;
                              _activeBand = i;
                            }),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _freqShort(i),
                      style: TextStyle(
                        fontSize: 8,
                        fontFamily: FnText.monoFamily.first,
                        color: i == _activeBand
                            ? FnColors.lime
                            : FnColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _freqShort(int i) {
    final f = _freqs[i];
    return f >= 1000 ? '${(f / 1000).toStringAsFixed(0)}k' : f.toInt().toString();
  }

  String _bandLabel(int i) {
    final f = _freqs[i];
    return f >= 1000 ? '${(f / 1000).toStringAsFixed(1)} kHz' : '${f.toInt()} Hz';
  }

  String _fmtGain(double v) =>
      '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB';

  Widget _sliderRow({
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    int? divisions,
    String? foot,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14, color: FnColors.textPrimary)),
              const Spacer(),
              Text(valueLabel,
                  style: TextStyle(
                      fontSize: 12.5,
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
              min: min,
              max: max,
              divisions: divisions,
              value: value,
              onChanged: onChanged,
              onChangeEnd: onEnd,
            ),
          ),
          if (foot != null)
            Text(foot,
                style: TextStyle(fontSize: 10, color: FnColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _meterCard() {
    final leftDb = _meterL <= 0 ? -60.0 : 20 * math.log(_meterL) / math.ln10;
    final rightDb = _meterR <= 0 ? -60.0 : 20 * math.log(_meterR) / math.ln10;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kFnPad),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.md),
        border: Border.all(color: FnColors.line),
      ),
      child: Column(
        children: [
          _meterRow('L', _meterL, leftDb),
          const SizedBox(height: 8),
          _meterRow('R', _meterR, rightDb),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: FnColors.line)),
            ),
            child: Row(
              children: [
                Text('HEADROOM · ${_headroom ? "6.0" : "0.0"} dB',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontFamily: FnText.monoFamily.first,
                        color: FnColors.textTertiary)),
                const Spacer(),
                Text('DSP 48 kHz / 32-bit float',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontFamily: FnText.monoFamily.first,
                        color: FnColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meterRow(String label, double value, double db) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textTertiary)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: FnColors.surface3,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(
                    colors: value > 0.82
                        ? [FnColors.lime, FnColors.coral]
                        : [FnColors.lime, FnColors.lime],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(db <= -59 ? '−∞' : db.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 9.5,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textSecondary)),
        ),
      ],
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  _EqCurvePainter({
    required this.gains,
    required this.showDots,
    required this.activeBand,
  });

  final List<double> gains;
  final bool showDots;
  final int activeBand;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final h = size.height;
    final w = size.width;
    final mid = h / 2;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = FnColors.line;

    for (final f in const [0.0, 0.28, 0.5, 0.72, 1.0]) {
      final y = pad + (h - pad * 2) * f;
      grid.color = f == 0.5 ? FnColors.line2 : FnColors.line;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    if (gains.isEmpty) return;
    final pts = <Offset>[];
    for (var i = 0; i < gains.length; i++) {
      final x = gains.length == 1 ? w / 2 : i / (gains.length - 1) * w;
      final y = (mid - gains[i] * (h - pad * 2) / 24).clamp(pad, h - pad);
      pts.add(Offset(x, y));
    }

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    final fill = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FnColors.lime.withValues(alpha: 0.32),
            FnColors.lime.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = FnColors.lime,
    );

    if (showDots) {
      for (var i = 0; i < pts.length; i++) {
        final on = i == activeBand;
        canvas.drawCircle(
            pts[i],
            on ? 3.6 : 2.4,
            Paint()
              ..color = on
                  ? FnColors.lime
                  : FnColors.lime.withValues(alpha: 0.65));
      }
    }
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      old.showDots != showDots ||
      old.activeBand != activeBand ||
      old.gains.length != gains.length ||
      !_same(old.gains, gains);

  bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

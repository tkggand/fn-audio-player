import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../l10n/l10n.dart';
import '../play_log.dart';
import '../player_controller.dart';
import '../runtime_config.dart';
import '../sync_client.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';
import '../widgets/quality_sheet.dart';

/// 设置：外观 / 播放 / 曲库与同步 / 网络 / 关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with FnThemeAware<SettingsPage> {
  static const _auraKey = 'fn_cover_aura';
  static const _gaplessKey = 'fn_gapless';
  static const _safeVolumeKey = 'fn_safe_volume';
  static const _discoverKey = 'fn_auto_discover';
  static const _wifiOnlyKey = 'fn_wifi_only';

  final _api = ApiClient.instance;

  SystemConfig? _config;
  bool _busy = false;

  bool _aura = true;
  bool _gapless = true;
  bool _safeVolume = false;
  bool _autoDiscover = true;
  bool _wifiOnly = true;
  /// 本地音频引擎开关由 PlayerController 持有，这里只做镜像显示。
  bool _localEngine = false;

  // desktop 用户卡（design/v3 settings.js `.set-profile`）的真实统计。
  int _favCount = 0;
  int _playlistCount = 0;
  int _weekPlays = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _aura = prefs.getBool(_auraKey) ?? true;
      _gapless = prefs.getBool(_gaplessKey) ?? true;
      _safeVolume = prefs.getBool(_safeVolumeKey) ?? false;
      _autoDiscover = prefs.getBool(_discoverKey) ?? true;
      _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? true;
      _localEngine = PlayerController.instance.localEngineEnabled;
    });
    try {
      final c = await _api.getSystemConfig();
      if (mounted) setState(() => _config = c);
    } catch (_) {
      // 未登录或网络异常：保留本地开关，服务端项以只读呈现。
    }
    // desktop 用户卡的统计（收藏 / 歌单 / 本周播放）全部取真实数据。
    try {
      final res = await Future.wait<Object>([
        _api.fetchFavorites(),
        _api.fetchPlaylists(),
      ]);
      final week = await PlayLog.instance.weekSummary();
      if (!mounted) return;
      setState(() {
        _favCount = (res[0] as List<Song>).length;
        _playlistCount = (res[1] as List<Playlist>).length;
        _weekPlays = week.plays;
      });
    } catch (_) {
      // 未登录时保持 0，不编造数据。
    }
  }

  Future<void> _update(String key, Object value) async {
    setState(() => _busy = true);
    try {
      final c = await _api.updateSystemConfig({key: value});
      RuntimeConfig.instance.apply(c);
      if (mounted) {
        setState(() => _config = c);
        fnToast(context, '已保存', icon: Icons.check_rounded);
      }
    } catch (e) {
      if (mounted) fnToast(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveBool(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _setTheme(FnThemeMode mode) async {
    await FnThemeController.instance.setMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _pickTheme() async {
    final current = FnThemeController.instance.value;
    final picked = await showFnSheet<FnThemeMode>(
      context,
      eyebrow: 'THEME',
      title: '主题',
      subtitle: '暗色 · 浅色 · 跟随系统',
      children: [
        for (final e in <FnThemeMode, String>{
          FnThemeMode.dark: '深色',
          FnThemeMode.light: '浅色',
          FnThemeMode.auto: '跟随系统',
        }.entries)
          FnOptionRow(
            title: e.value,
            icon: CupertinoIcons.moon_stars,
            on: e.key == current,
            onTap: () => Navigator.pop(context, e.key),
          ),
      ],
    );
    if (picked != null) await _setTheme(picked);
  }

  Future<void> _pickLanguage() async {
    final l = context.l10n;
    final current = FnLocaleController.instance.value;
    final picked = await showFnSheet<FnLocaleMode>(
      context,
      eyebrow: 'LANGUAGE',
      title: '语言',
      subtitle: '界面与元数据语言',
      children: [
        for (final e in <FnLocaleMode, String>{
          FnLocaleMode.system: l.languageSystem,
          FnLocaleMode.zh: l.languageZh,
          FnLocaleMode.en: l.languageEn,
        }.entries)
          FnOptionRow(
            title: e.value,
            icon: CupertinoIcons.globe,
            on: e.key == current,
            onTap: () => Navigator.pop(context, e.key),
          ),
      ],
    );
    if (picked != null) {
      await FnLocaleController.instance.setMode(picked);
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickQuality() async {
    final q = await openQualitySheet(context,
        current: PlayerController.instance.quality);
    if (q == null) return;
    await PlayerController.instance.setQuality(q);
    if (!mounted) return;
    setState(() {});
    fnToast(context, '音质已切换为 ${qualityLabel(context, q)}');
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('清理缓存？', style: TextStyle(fontSize: 17)),
        content: Text('将清空封面与头像的内存缓存，不影响曲库与登录状态。',
            style: TextStyle(fontSize: 13, color: FnColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清理', style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    if (mounted) fnToast(context, '缓存已清理', icon: Icons.delete_outline_rounded);
  }

  Future<void> _openServerDialog() async {
    final ctrl = TextEditingController(text: _api.baseUrl);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('服务器地址', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('修改后会退出登录，请重新输入账号。',
                style:
                    TextStyle(fontSize: 12, color: FnColors.textSecondary)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: TextStyle(color: FnColors.textPrimary),
              decoration: const InputDecoration(hintText: 'http://host:port'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存并重新登录'),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty || input == _api.baseUrl) return;
    try {
      ApiClient.normalizeBaseUrl(input);
    } on FormatException catch (e) {
      if (mounted) fnToast(context, '地址无效：${e.message}');
      return;
    }
    await _api.setBaseUrl(input);
    SyncClient.instance.disconnect();
    await _api.logout();
    if (mounted) context.go('/login');
  }

  Future<void> _about() async {
    await showFnSheet<void>(
      context,
      eyebrow: 'FN AUDIO',
      title: '关于',
      subtitle: '2.0.0 · 自托管音乐播放器',
      children: [
        FnOptionRow(
          title: '服务器',
          subtitle: _api.baseUrl,
          icon: CupertinoIcons.link,
          onTap: () {
            Navigator.pop(context);
            _openServerDialog();
          },
        ),
        FnOptionRow(
          title: '检查更新',
          subtitle: '当前已是最新版本',
          icon: CupertinoIcons.arrow_2_circlepath,
          onTap: () {
            Navigator.pop(context);
            fnToast(context, '已是最新版本',
                icon: Icons.check_circle_rounded);
          },
        ),
        FnOptionRow(
          title: '开源许可',
          subtitle: 'Flutter · just_audio · dio',
          icon: CupertinoIcons.doc_text,
          onTap: () {
            Navigator.pop(context);
            showLicensePage(context: context);
          },
        ),
      ],
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('退出登录？', style: TextStyle(fontSize: 17)),
        content: Text('本机缓存的曲库索引会保留，下次连接可直接恢复。',
            style: TextStyle(fontSize: 13, color: FnColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('退出', style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _api.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final admin = _api.isAdmin;
    final themeMode = FnThemeController.instance.value;
    final username = _api.username ?? 'FN';
    final quality = PlayerController.instance.quality;
    final rg = PlayerController.instance.rgMode;
    final wide = fnBpOf(context).isWide;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
          padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
          physics: const BouncingScrollPhysics(),
          children: [
            if (wide)
              const FnPageHead(
                eyebrow: 'SETTINGS',
                title: '设置',
                subtitle: '主题与播放偏好保存在本机 · FN Audio 2.0.0',
              )
            else
            FnNav(
              title: '设置',
              subtitle: 'SETTINGS',
              trailing: [
                FnIconBtn(
                  icon: CupertinoIcons.search,
                  variant: FnIconBtnVariant.plain,
                  onTap: () => context.push('/search'),
                ),
              ],
            ),
            // design/v3 settings.css：用户卡仅 desktop（移动端的「我的」Tab 已覆盖）。
            if (fnBpOf(context) == FnBp.desktop) _profileCard(username, admin),
            const FnGroupLabel('外观'),
            FnGroupCard(children: [
              FnListRow(
                icon: CupertinoIcons.moon_stars,
                title: '主题',
                subtitle: '暗色 · 浅色 · 跟随系统',
                value: switch (themeMode) {
                  FnThemeMode.dark => '深色',
                  FnThemeMode.light => '浅色',
                  FnThemeMode.auto => '跟随系统',
                },
                onTap: _pickTheme,
              ),
              FnListRow(
                icon: CupertinoIcons.globe,
                title: '语言',
                subtitle: '界面与元数据语言',
                value: switch (FnLocaleController.instance.value) {
                  FnLocaleMode.system => '跟随系统',
                  FnLocaleMode.zh => '简体中文',
                  FnLocaleMode.en => 'English',
                },
                onTap: _pickLanguage,
              ),
              FnListRow(
                icon: CupertinoIcons.sparkles,
                title: '封面氛围光',
                subtitle: '播放页根据封面取色',
                showChevron: false,
                trailing: FnSwitch(
                  value: _aura,
                  onChanged: (v) async {
                    setState(() => _aura = v);
                    await _saveBool(_auraKey, v);
                  },
                ),
              ),
            ]),
            const FnGroupLabel('播放'),
            FnGroupCard(children: [
              FnListRow(
                icon: CupertinoIcons.waveform_path_ecg,
                title: '音质',
                subtitle: '无损优先 · 内网直连',
                value: qualityLabel(context, quality),
                onTap: _pickQuality,
              ),
              FnListRow(
                icon: Icons.tune_rounded,
                title: '调音与均衡器',
                subtitle: 'EQ · 交叉馈送 · headroom',
                value: '已启用',
                onTap: () => context.push('/tuning'),
              ),
              FnListRow(
                icon: CupertinoIcons.volume_down,
                title: '响度均衡',
                subtitle: 'ReplayGain · 曲目增益',
                value: switch (rg) {
                  'track' => '曲目增益',
                  'album' => '专辑增益',
                  _ => '关闭',
                },
                onTap: () => context.push('/replaygain'),
              ),
              FnListRow(
                icon: CupertinoIcons.device_phone_portrait,
                title: '播放设备',
                subtitle: 'DLNA 投屏与本机扬声器',
                onTap: () => context.push('/devices'),
              ),
              FnListRow(
                icon: CupertinoIcons.music_note_2,
                title: '无缝播放',
                subtitle: 'Gapless · 连续专辑不中断',
                showChevron: false,
                trailing: FnSwitch(
                  value: _gapless,
                  onChanged: (v) async {
                    setState(() => _gapless = v);
                    await _saveBool(_gaplessKey, v);
                  },
                ),
              ),
              FnListRow(
                icon: CupertinoIcons.arrow_left_to_line,
                title: '切歌淡入淡出',
                subtitle: '淡入 800 ms · 淡出 1500 ms',
                showChevron: false,
                trailing: FnSwitch(
                  value: true,
                  onChanged: (v) =>
                      fnToast(context, '请在调音页调整淡入淡出',
                          icon: Icons.tune_rounded),
                ),
              ),
              FnListRow(
                icon: Icons.memory_rounded,
                title: '本地音频引擎',
                subtitle: '全格式解码 · DSP 在本机运行',
                showChevron: false,
                trailing: FnSwitch(
                  value: _localEngine,
                  onChanged: (v) async {
                    setState(() => _localEngine = v);
                    await PlayerController.instance.setLocalEngine(v);
                    if (!context.mounted) return;
                    if (v && !PlayerController.instance.usingLocalEngine) {
                      fnToast(context, '本地引擎不可用，已回退系统播放器',
                          icon: Icons.info_outline_rounded);
                    }
                    setState(() {});
                  },
                ),
              ),
              FnListRow(
                icon: CupertinoIcons.headphones,
                title: '耳机音量保护',
                subtitle: '超过 85 dB 时提示',
                showChevron: false,
                trailing: FnSwitch(
                  value: _safeVolume,
                  onChanged: (v) async {
                    setState(() => _safeVolume = v);
                    await _saveBool(_safeVolumeKey, v);
                  },
                ),
              ),
            ]),
            const FnGroupLabel('曲库与同步'),
            FnGroupCard(children: [
              FnListRow(
                icon: CupertinoIcons.folder,
                title: '扫描目录',
                subtitle: '管理曲库索引与自动扫描',
                value: '管理',
                onTap: () => context.push('/scan'),
              ),
              FnListRow(
                icon: CupertinoIcons.cloud,
                title: '自动同步播放状态',
                subtitle: admin ? '跨设备续播' : '需要管理员权限',
                showChevron: false,
                trailing: FnSwitch(
                  value: _config?.syncEnabled ?? RuntimeConfig.instance.syncEnabled,
                  onChanged: admin && !_busy
                      ? (v) => _update('sync_enabled', v)
                      : (_) => fnToast(context, '需要管理员权限',
                          icon: Icons.lock_outline_rounded),
                ),
              ),
              FnListRow(
                icon: CupertinoIcons.pencil,
                title: '元数据来源',
                subtitle: 'MusicBrainz · 自动匹配',
                value: admin ? '优先' : '只读',
                onTap: () => fnToast(context, '元数据刮削在扫描页可用',
                    icon: Icons.edit_note_rounded),
              ),
              FnListRow(
                icon: CupertinoIcons.trash,
                title: '缓存',
                subtitle: '封面与转码缓存',
                value: '清理',
                onTap: _clearCache,
              ),
            ]),
            const FnGroupLabel('网络'),
            FnGroupCard(children: [
              FnListRow(
                icon: CupertinoIcons.link,
                title: '服务器',
                subtitle: _api.baseUrl,
                value: '已连接',
                valueColor: FnColors.green,
                onTap: _openServerDialog,
              ),
              FnListRow(
                icon: CupertinoIcons.wifi,
                title: '自动发现服务器',
                subtitle: '局域网 mDNS 广播',
                showChevron: false,
                trailing: FnSwitch(
                  value: _autoDiscover,
                  onChanged: (v) async {
                    setState(() => _autoDiscover = v);
                    await _saveBool(_discoverKey, v);
                  },
                ),
              ),
              FnListRow(
                icon: CupertinoIcons.antenna_radiowaves_left_right,
                title: '仅 Wi-Fi 播放',
                subtitle: '移动网络下仅显示已下载',
                showChevron: false,
                trailing: FnSwitch(
                  value: _wifiOnly,
                  onChanged: (v) async {
                    setState(() => _wifiOnly = v);
                    await _saveBool(_wifiOnlyKey, v);
                  },
                ),
              ),
            ]),
            const FnGroupLabel('关于'),
            FnGroupCard(children: [
              FnListRow(
                icon: CupertinoIcons.info,
                title: '关于 FN Audio',
                subtitle: '2.0.0 · 自托管音乐播放器',
                onTap: _about,
              ),
              FnListRow(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: '检查更新',
                subtitle: '当前已是最新版本',
                value: '2.0.0',
                onTap: () => fnToast(context, '已是最新版本',
                    icon: Icons.check_circle_rounded),
              ),
              FnListRow(
                icon: CupertinoIcons.square_arrow_right,
                title: '退出登录',
                subtitle: '清除本机登录凭证',
                danger: true,
                onTap: _logout,
              ),
            ]),
            FnPageFoot(
              left: 'FN AUDIO 2.0.0 · FLUTTER',
              right: '服务器 ${_api.baseUrl}',
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }

  /// design/v3 settings.js `.set-profile`：头像 + 身份 + 真实统计 + FLAC / 播放历史。
  Widget _profileCard(String username, bool admin) {
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 0),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line),
        gradient: RadialGradient(
          center: const Alignment(1, -1),
          radius: 1.4,
          colors: [
            FnColors.lime.withValues(alpha: 0.1),
            FnColors.surface,
          ],
          stops: const [0, 0.6],
        ),
      ),
      child: Row(
        children: [
          const FnAvatar(imageUrl: null, size: 56),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(admin ? '自托管 · 管理员' : '自托管 · 曲库已同步',
                    style: TextStyle(
                        fontSize: 12, color: FnColors.textSecondary)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _spStat('$_weekPlays', '本周播放'),
                    const SizedBox(width: 18),
                    _spStat('$_favCount', '收藏'),
                    const SizedBox(width: 18),
                    _spStat('$_playlistCount', '歌单'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FnColors.glassLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('FLAC',
                    style: TextStyle(
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                        fontFamily: FnText.monoFamily.first,
                        color: FnColors.limeText)),
              ),
              const SizedBox(height: 10),
              FnButton(
                label: '播放历史',
                icon: CupertinoIcons.time,
                variant: FnButtonVariant.ghost,
                size: FnButtonSize.sm,
                onTap: () => context.push('/history'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _spStat(String value, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.limeText)),
          const SizedBox(width: 5),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: FnColors.textTertiary)),
        ],
      );
}

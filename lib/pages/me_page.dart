import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../play_log.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/fn_ui.dart';
import '../widgets/quality_sheet.dart';

/// 我的：资料头部 + 统计 + 快捷入口 + 本周聆听 + 音频/系统设置。
class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> with FnThemeAware<MePage> {
  List<Song> _songs = const [];
  List<Song> _favs = const [];
  List<Playlist> _playlists = const [];
  List<int> _week = const [0, 0, 0, 0, 0, 0, 0];
  int _weekPlays = 0;
  int _weekSeconds = 0;
  String? _topArtist;
  int _deviceCount = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _syncing = true;
    });
    try {
      final res = await Future.wait<Object>([
        ApiClient.instance.fetchSongs(),
        ApiClient.instance.fetchFavorites(),
        ApiClient.instance.fetchPlaylists(),
      ]);
      final week = await PlayLog.instance.weekCounts();
      final summary = await PlayLog.instance.weekSummary();
      var devices = 0;
      try {
        devices = (await ApiClient.instance.dlnaRenderers()).length;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _songs = res[0] as List<Song>;
        _favs = res[1] as List<Song>;
        _playlists = res[2] as List<Playlist>;
        _week = week;
        _weekPlays = summary.plays;
        _weekSeconds = summary.seconds;
        _topArtist = summary.topArtist;
        _deviceCount = devices;
        _syncing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
      });
    }
  }

  Future<void> _pickQuality() async {
    final q = await openQualitySheet(context, current: PlayerController.instance.quality);
    if (q != null) {
      await PlayerController.instance.setQuality(q);
      if (!mounted) return;
      fnToast(context, '音质已切换为 ${qualityLabel(context, q)}');
      setState(() {});
    }
  }

  void _pickLanguage() {
    showFnSheet<void>(
      context,
      eyebrow: 'LANGUAGE',
      title: '界面语言',
      subtitle: '通用导航与标签会同步切换',
      children: [
        for (final (mode, label) in [
          (FnLocaleMode.system, '跟随系统'),
          (FnLocaleMode.zh, '简体中文'),
          (FnLocaleMode.en, 'English'),
        ])
          FnOptionRow(
            title: label,
            icon: CupertinoIcons.globe,
            on: FnLocaleController.instance.value == mode,
            onTap: () async {
              Navigator.pop(context);
              await FnLocaleController.instance.setMode(mode);
              if (mounted) fnToast(context, '已切换为$label');
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
        content: Text(
          '本机缓存的曲库索引会保留，下次连接可直接恢复。',
          style: TextStyle(fontSize: 13, color: FnColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('退出',
                style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiClient.instance.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final username = ApiClient.instance.username ?? 'FN';
    final coverId = PlayerController.instance.current?.id ??
        (_favs.isNotEmpty ? _favs.first.id : 59);
    final themeMode = FnThemeController.instance.value;
    final weekSeed = _week.reduce((a, b) => a + b);
    final bars = weekSeed == 0
        ? const [0, 0, 0, 0, 0, 0, 0]
        : _week.map((v) => v).toList();
    final maxBar = bars.fold<int>(1, (m, v) => v > m ? v : m);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _load,
        color: FnColors.lime,
        backgroundColor: FnColors.surface,
        child: ListView(
          padding: const EdgeInsets.only(bottom: kFnDockInset + 12),
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          children: [
            _Hero(
              coverId: coverId,
              name: username,
              trackCount: _songs.length,
              syncing: _syncing,
              onSync: _load,
            ),
            Transform.translate(
              offset: const Offset(0, -24),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                    child: Row(
                      children: [
                        Expanded(
                          child: FnStatTile(
                            value: '$_weekPlays',
                            label: '本周播放',
                            highlight: true,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FnStatTile(
                              value: '${_favs.length}', label: '收藏歌曲'),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FnStatTile(
                              value: '${_playlists.length}', label: '我的歌单'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                    child: Row(
                      children: [
                        Expanded(
                          child: FnQuickTile(
                            icon: CupertinoIcons.heart_fill,
                            label: '收藏',
                            onTap: () => context.push('/library?tab=favorites'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FnQuickTile(
                            icon: CupertinoIcons.clock,
                            label: '历史',
                            onTap: () => context.push('/history'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FnQuickTile(
                            icon: Icons.queue_music_rounded,
                            label: '歌单',
                            onTap: () => context.push('/playlists'),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: FnQuickTile(
                            icon: Icons.qr_code_scanner_rounded,
                            label: '扫描',
                            onTap: () => context.push('/scan'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            FnSectionHead(
              title: '本周聆听',
              sub: _weekPlays == 0
                  ? '还没有记录'
                  : '$_weekPlays 首 · ${(_weekSeconds / 3600).toStringAsFixed(1)} 小时',
            ),
            _WeekCard(
              bars: bars,
              maxBar: maxBar,
              topArtist: _topArtist,
              onOpenHistory: () => context.push('/history'),
            ),
            const FnGroupLabel('音频'),
            FnGroupCard(children: [
              FnListRow(
                title: '音质',
                subtitle: '内网优先无损',
                icon: Icons.graphic_eq_rounded,
                value: qualityLabel(context, PlayerController.instance.quality),
                valueColor: FnColors.limeText,
                onTap: _pickQuality,
              ),
              FnListRow(
                title: '调音',
                subtitle: 'GEQ · 交叉馈送 · 淡入淡出',
                icon: CupertinoIcons.slider_horizontal_3,
                value: '原声纯净',
                valueColor: FnColors.limeText,
                onTap: () => context.push('/tuning'),
              ),
              FnListRow(
                title: 'ReplayGain',
                subtitle: '响度归一与批量分析',
                icon: Icons.waves_rounded,
                onTap: () => context.push('/replaygain'),
              ),
              FnListRow(
                title: '播放设备',
                subtitle: _deviceCount > 0
                    ? '$_deviceCount 台 DLNA 在线'
                    : '未发现 DLNA 渲染器',
                icon: CupertinoIcons.device_phone_portrait,
                value: PlayerController.instance.isCasting ? '投屏中' : '本机扬声器',
                onTap: () => context.push('/devices'),
              ),
            ]),
            const FnGroupLabel('系统'),
            FnGroupCard(children: [
              Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: FnColors.glassLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        themeMode.isDark
                            ? CupertinoIcons.moon
                            : CupertinoIcons.sun_max,
                        size: 18,
                        color: FnColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('主题',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: FnColors.textPrimary)),
                          Text(
                            themeMode.isDark
                                ? '跟随音乐，保持暗色'
                                : '浅色 · 适合白天浏览',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: FnColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    FnSwitch(
                      value: themeMode.isDark,
                      onChanged: (v) async {
                        await FnThemeController.instance.setMode(
                            v ? FnThemeMode.dark : FnThemeMode.light);
                        if (!context.mounted) return;
                        fnToast(
                          context,
                          v ? '已切换到暗色主题' : '已切换到浅色主题',
                          icon: v ? CupertinoIcons.moon : CupertinoIcons.sun_max,
                        );
                      },
                    ),
                  ],
                ),
              ),
              FnListRow(
                title: '语言',
                subtitle: '界面与元数据',
                icon: CupertinoIcons.globe,
                value: switch (FnLocaleController.instance.value) {
                  FnLocaleMode.zh => '简体中文',
                  FnLocaleMode.en => 'English',
                  FnLocaleMode.system => '跟随系统',
                },
                onTap: _pickLanguage,
              ),
              FnListRow(
                title: '设置',
                subtitle: '同步、自动播放、关于',
                icon: CupertinoIcons.gear,
                onTap: () => context.push('/settings'),
              ),
              FnListRow(
                title: '退出登录',
                subtitle: '返回服务器连接页',
                icon: CupertinoIcons.square_arrow_right,
                danger: true,
                onTap: _logout,
              ),
            ]),
            FnPageFoot(
              left: 'FN AUDIO v2.0 · SELF-HOSTED',
              right: '${_songs.length} TRACKS',
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.coverId,
    required this.name,
    required this.trackCount,
    required this.syncing,
    required this.onSync,
  });

  final int coverId;
  final String name;
  final int trackCount;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: SizedBox(
        height: top + 268,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Transform.scale(
                scale: 1.12,
                child: Image.network(
                  ApiClient.instance.coverUrl(coverId),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      DecoratedBox(decoration: BoxDecoration(
                          gradient: fnCoverGradient(coverId))),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0x52050608),
                    const Color(0x80050608),
                    FnColors.base,
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.86, -0.9),
                  radius: 0.8,
                  colors: [
                    FnColors.lime.withValues(alpha: 0.2),
                    Colors.transparent
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(kFnPad, top + 8, kFnPad, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'MY LIBRARY',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.68,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.push('/settings'),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: const Icon(CupertinoIcons.gear,
                              size: 17, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              FnColors.lime,
                              FnColors.lime.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: FnCover(songId: coverId, size: 72, radius: 36),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 30,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.5,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                _Pill(
                                  label: '自托管',
                                  dotColor: FnColors.lime,
                                ),
                                const SizedBox(width: 6),
                                const _Pill(label: 'FN-Audio v2'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onSync,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.cloud,
                              size: 14, color: FnColors.lime),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              syncing
                                  ? '正在与服务器同步…'
                                  : '已同步 $trackCount 首 · 点击刷新',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                            ),
                          ),
                          Icon(CupertinoIcons.arrow_clockwise,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.38)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.dotColor});
  final String label;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.bars,
    required this.maxBar,
    required this.topArtist,
    required this.onOpenHistory,
  });

  final List<int> bars;
  final int maxBar;
  final String? topArtist;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    final today = (DateTime.now().weekday + 6) % 7;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kFnPad),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.md),
        border: Border.all(color: FnColors.line),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                              duration: Duration(milliseconds: 420 + i * 40),
                              curve: Curves.easeOutCubic,
                              width: 22,
                              height: bars[i] == 0
                                  ? 3
                                  : (78.0 * bars[i] / maxBar).clamp(6, 78),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                  bottom: Radius.circular(3),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: i == today
                                      ? [
                                          FnColors.lime,
                                          FnColors.lime.withValues(alpha: 0.35)
                                        ]
                                      : [
                                          FnColors.lime.withValues(alpha: 0.9),
                                          FnColors.lime.withValues(alpha: 0.18)
                                        ],
                                ),
                                boxShadow: i == today
                                    ? [
                                        BoxShadow(
                                          color: FnColors.lime
                                              .withValues(alpha: 0.5),
                                          blurRadius: 18,
                                          spreadRadius: -4,
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          days[i],
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: FnText.monoFamily.first,
                            color: i == today
                                ? FnColors.lime
                                : FnColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 13),
          Container(height: 1, color: FnColors.line),
          const SizedBox(height: 11),
          Row(
            children: [
              if (topArtist != null) ...[
                FnArtistAvatar(name: topArtist!, size: 20),
                const SizedBox(width: 7),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '本周听得最多：',
                      style: TextStyle(
                          fontSize: 10.5, color: FnColors.textSecondary),
                      children: [
                        TextSpan(
                          text: topArtist,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: FnColors.textPrimary),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    '开始播放后，这里会显示本周足迹',
                    style: TextStyle(
                        fontSize: 10.5, color: FnColors.textSecondary),
                  ),
                ),
              GestureDetector(
                onTap: onOpenHistory,
                child: Row(
                  children: [
                    Text(
                      '查看历史',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: FnColors.textSecondary,
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_forward,
                        size: 12, color: FnColors.textTertiary),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

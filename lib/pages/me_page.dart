import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../play_log.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/fn_ui.dart';
import '../widgets/history_cover_wall.dart';

/// 我的：资料头部 + 统计 + 快捷入口 + 本周聆听。
class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> with FnThemeAware<MePage> {
  List<Song> _songs = const [];
  List<Song> _favs = const [];
  List<Playlist> _playlists = const [];
  List<Song> _history = const [];
  List<int> _week = const [0, 0, 0, 0, 0, 0, 0];
  int _weekPlays = 0;
  int _weekSeconds = 0;
  String? _topArtist;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 单个请求失败后按 300ms / 900ms 退避重试，最多 3 次。
  ///
  /// 首次进入页面时偶发网络/鉴权抖动会让某一块数据缺失，
  /// 表现为「只显示一部分，必须下拉刷新才完整」，重试可避免这种残缺首屏。
  Future<T?> _loadRetry<T>(Future<T> Function() task) async {
    const delays = [300, 900];
    for (var i = 0;; i++) {
      try {
        return await task();
      } catch (_) {
        if (i >= delays.length) return null;
        await Future<void>.delayed(Duration(milliseconds: delays[i]));
      }
    }
  }

  /// 历史封面墙自愈：首次进入时后端可能尚未就绪，
  /// 按递增间隔重试，拿到即渲染，避免依赖用户手动下拉。
  Future<void> _healHistory() async {
    const delays = [600, 1200, 2500, 5000];
    for (final ms in delays) {
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!mounted || _history.isNotEmpty) return;
      final again =
          await _loadRetry(() => ApiClient.instance.fetchHistory(limit: 24));
      if (!mounted || again == null || again.isEmpty) continue;
      setState(() {
        _history = again;
      });
      return;
    }
  }

  Future<void> _load() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
    });
    // 1) 历史优先：先拿到就可以渲染封面墙，首屏立即有内容。
    final history =
        await _loadRetry(() => ApiClient.instance.fetchHistory(limit: 24));
    if (!mounted) return;
    if (history != null && history.isNotEmpty) {
      setState(() {
        _history = history;
      });
    } else {
      // 首次没拿到历史（后端 / 网络尚未就绪）：按递增间隔自补几次，
      // 让封面墙自己出现，而不是必须由用户下拉刷新触发。
      _healHistory();
    }
    // 2) 其余数据并行加载；单项失败时保留旧值，不影响其它区块。
    final songsF = _loadRetry(() => ApiClient.instance.fetchSongs());
    final favsF = _loadRetry(() => ApiClient.instance.fetchFavorites());
    final playlistsF = _loadRetry(() => ApiClient.instance.fetchPlaylists());
    final weekF = _loadRetry(() => PlayLog.instance.weekCounts());
    final summaryF = _loadRetry(() => PlayLog.instance.weekSummary());
    final songs = await songsF;
    final favs = await favsF;
    final playlists = await playlistsF;
    final week = await weekF;
    final summary = await summaryF;
    if (!mounted) return;
    setState(() {
      _songs = songs ?? _songs;
      _favs = favs ?? _favs;
      _playlists = playlists ?? _playlists;
      _week = week ?? _week;
      _weekPlays = summary?.plays ?? _weekPlays;
      _weekSeconds = summary?.seconds ?? _weekSeconds;
      _topArtist = summary?.topArtist ?? _topArtist;
      _syncing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final username = ApiClient.instance.username ?? 'FN';
    final coverId = PlayerController.instance.current?.id ??
        (_favs.isNotEmpty ? _favs.first.id : 59);
    final weekSeed = _week.reduce((a, b) => a + b);
    final bars = weekSeed == 0
        ? const [0, 0, 0, 0, 0, 0, 0]
        : _week.map((v) => v).toList();
    final maxBar = bars.fold<int>(1, (m, v) => v > m ? v : m);
    // 移动端顶部历史播放封面墙；无历史时不占位，头部恢复自带状态栏留白。
    final showWall = fnBpOf(context).isMobile && _history.isNotEmpty;
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
            if (showWall)
              HistoryCoverWall(
                songs: _history,
                onTap: (song) => PlayerController.instance.playOne(song),
              ),
            // 头部背景是模糊图层，独立成层避免每次封面墙位移都重新模糊。
            RepaintBoundary(
              child: _Hero(
                coverId: coverId,
                name: username,
                trackCount: _songs.length,
                syncing: _syncing,
                onSync: _load,
                topInset: showWall ? 8 : null,
              ),
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
    this.topInset,
  });

  final int coverId;
  final String name;
  final int trackCount;
  final bool syncing;
  final VoidCallback onSync;

  /// 顶部留白；上方有封面墙时传小值，否则按状态栏高度留白。
  final double? topInset;

  @override
  Widget build(BuildContext context) {
    final top = topInset ?? MediaQuery.paddingOf(context).top;
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
                  errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration:
                          BoxDecoration(gradient: fnCoverGradient(coverId))),
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

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 发现：每日推荐、漫游入口、关注歌手、最近播放、精选歌单、流派、新进专辑。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with FnThemeAware<DiscoverPage> {
  bool _loading = true;
  String? _error;

  List<Song> _songs = const [];
  List<DailyRecItem> _daily = const [];
  List<FollowedArtist> _artists = const [];
  List<Song> _history = const [];
  List<Playlist> _playlists = const [];
  List<GenreInfo> _genres = const [];
  List<AggregateItem> _albums = const [];

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
    try {
      final res = await Future.wait<Object>([
        ApiClient.instance.fetchSongs(),
        ApiClient.instance.fetchDailyRecommendations(),
        ApiClient.instance.fetchFollowedArtists(),
        ApiClient.instance.fetchHistory(limit: 12),
        ApiClient.instance.fetchPlaylists(),
        ApiClient.instance.fetchGenres(),
        ApiClient.instance.fetchAggregate(by: 'album', pageSize: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _songs = res[0] as List<Song>;
        _daily = (res[1] as DailyRecommendations).items;
        _artists = res[2] as List<FollowedArtist>;
        _history = res[3] as List<Song>;
        _playlists = res[4] as List<Playlist>;
        _genres = res[5] as List<GenreInfo>;
        _albums = (res[6] as AggregatePage).items;
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

  List<Song> get _dailySongs {
    if (_daily.isNotEmpty) return _daily.map((d) => d.song).toList();
    return _songs.take(10).toList();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? '早上好' : (h < 18 ? '下午好' : '晚上好');
  }

  /// design/v3 js/pages/discover.js `W[now.getDay()]`：周日在前。
  static const _weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

  String get _weekday => _weekdays[DateTime.now().weekday % 7];

  /// design/v3 js/pages/discover.js dateLine：`M月D日 · 周X`。
  String get _dateLine {
    final now = DateTime.now();
    return '${now.month}月${now.day}日 · $_weekday';
  }

  void _playDaily() {
    final list = _dailySongs;
    if (list.isEmpty) {
      fnToast(context, '推荐还在生成，稍后再试');
      return;
    }
    PlayerController.instance.playList(list, 0);
    fnToast(context, '已开始播放每日推荐 · ${list.length} 首',
        icon: Icons.play_arrow_rounded);
  }

  Future<void> _startRoam(String mode, String name) async {
    final ok = await PlayerController.instance.startRoam(mode, count: 20);
    if (!mounted) return;
    if (!ok) {
      fnToast(context, PlayerController.instance.lastError ?? '暂时没有可漫游的歌曲');
      return;
    }
    fnToast(context, '进入$name', icon: Icons.auto_awesome);
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: FnEmpty(
            icon: CupertinoIcons.exclamationmark_circle,
            title: '发现页加载失败',
            message: _error,
            actionLabel: '重试',
            onAction: _load,
          ),
        ),
      );
    }
    final daily = _dailySongs;
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
        physics: const BouncingScrollPhysics(),
        children: [
          FnPageHead(
            eyebrow: 'FOR YOU',
            title: _greeting,
            subtitle: '$_dateLine · 为你推荐',
            actions: [
              FnIconBtn(
                icon: CupertinoIcons.search,
                onTap: () => context.push('/search'),
              ),
            ],
          ),
          _DailyHero(
            songs: daily,
            day: now.day,
            month: now.month,
            weekday: _weekday,
            onPlay: _playDaily,
          ),
          // design/v3 js/pages/discover.js `quickMarkup`：4 快捷入口，
          // desktop 4 列 / laptop 2 列 / mobile 单列（css/pages/discover.css `.quick`）。
          Padding(
            padding: const EdgeInsets.fromLTRB(kFnPad, 14, kFnPad, 0),
            // 行高按设计稿固定：图标 38 + 上下内边距 14×2 = 66。
            // 不用 childAspectRatio（它随宽度反推行高），窄窗口下会把卡片压到
            // 放不下图标与两行文案，触发 Column 竖向溢出。
            child: GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: switch (fnBpOf(context)) {
                  FnBp.mobile => 1,
                  FnBp.laptop => 2,
                  FnBp.desktop => 4,
                },
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 66,
              ),
              children: [
                _QuickCard(
                  icon: Icons.auto_awesome,
                  title: '私人漫游',
                  sub: '按口味连续播放',
                  onTap: () => _startRoam('taste', '私人漫游'),
                ),
                _QuickCard(
                  icon: Icons.radio_rounded,
                  title: '收藏电台',
                  sub: '收藏曲目的不间断电台',
                  onTap: () => _startRoam('taste', '收藏电台'),
                ),
                _QuickCard(
                  icon: Icons.album_rounded,
                  title: '新歌速递',
                  sub: '曲库最新加入',
                  onTap: () => context.push('/songs'),
                ),
                _QuickCard(
                  icon: CupertinoIcons.waveform,
                  title: '流派浏览',
                  sub: '按流派探索曲库',
                  onTap: () => context.push('/library?tab=genres'),
                ),
              ],
            ),
          ),
          const FnSectionHead(title: '漫游', sub: '不间断的下一首'),
          SizedBox(
            height: 118,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kFnPad),
              children: [
                _RoamCard(
                  title: '私人漫游',
                  sub: '按口味连续播放',
                  icon: Icons.auto_awesome,
                  colors: const [Color(0xFF2B3A12), Color(0xFF141A12)],
                  onTap: () => _startRoam('taste', '私人漫游'),
                ),
                const SizedBox(width: 10),
                _RoamCard(
                  title: '相似歌曲',
                  sub: '沿着这一首继续',
                  icon: CupertinoIcons.waveform,
                  colors: const [Color(0xFF14293A), Color(0xFF111820)],
                  onTap: () => _startRoam('similar', '相似歌曲'),
                ),
                const SizedBox(width: 10),
                _RoamCard(
                  title: '随机漫游',
                  sub: '偶遇新的声音',
                  icon: Icons.shuffle_rounded,
                  colors: const [Color(0xFF2C1730), Color(0xFF19121C)],
                  onTap: () => _startRoam('random', '随机漫游'),
                ),
              ],
            ),
          ),
          if (_history.isNotEmpty) ...[
            FnSectionHead(
              title: '最近播放',
              actionLabel: '历史',
              onAction: () => context.push('/history'),
            ),
            SizedBox(
              height: 216,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                itemCount: _history.take(10).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final s = _history[i];
                  return FnArtCard(
                    songId: s.id,
                    title: s.title,
                    sub: '${s.artist} · ${fmtDuration(s.duration)}',
                    onTap: () {
                      PlayerController.instance.playList(_history, i);
                    },
                  );
                },
              ),
            ),
          ],
          FnSectionHead(
            title: '推荐歌单',
            actionLabel: '全部',
            onAction: () => context.push('/playlists'),
          ),
          if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad),
              child: GestureDetector(
                onTap: () => context.push('/playlists'),
                child: Container(
                  height: 92,
                  decoration: BoxDecoration(
                    color: FnColors.surface,
                    borderRadius: BorderRadius.circular(FnRadius.md),
                    border: Border.all(color: FnColors.line),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FnColors.limeSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.add_rounded,
                            color: FnColors.limeText),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('创建你的第一个歌单',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('把常听的歌整理到一起',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: FnColors.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (fnBpOf(context).isWide)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      fnGridCols(context, mobile: 2, laptop: 4, desktop: 6),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.76,
                ),
                itemCount: _playlists.length.clamp(0, 12),
                itemBuilder: (context, i) {
                  final p = _playlists[i];
                  return FnPlaylistCell(
                    title: p.name,
                    count: p.songCount,
                    coverSongId: p.coverSongId,
                    onTap: () => context.push('/playlist/${p.id}'),
                  );
                },
              ),
            )
          else
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                itemCount: _playlists.length.clamp(0, 10),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = _playlists[i];
                  return SizedBox(
                    width: 150,
                    child: FnPlaylistCell(
                      title: p.name,
                      count: p.songCount,
                      coverSongId: p.coverSongId,
                      onTap: () => context.push('/playlist/${p.id}'),
                    ),
                  );
                },
              ),
            ),
          if (_artists.isNotEmpty || _songs.isNotEmpty) ...[
            FnSectionHead(
              title: '推荐艺人',
              actionLabel: '全部',
              onAction: () => context.push('/library?tab=artists'),
            ),
            SizedBox(
              height: switch (fnBpOf(context)) {
                FnBp.mobile => 102,
                FnBp.laptop => 114,
                FnBp.desktop => 126,
              },
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                children: [
                  if (_artists.isNotEmpty)
                    ..._artists.take(8).map((a) => _ArtistPick(
                          name: a.name,
                          followed: true,
                          onTap: () => context
                              .push('/artist/${Uri.encodeComponent(a.name)}'),
                        ))
                  else
                    ..._uniqueArtists().take(8).map((name) => _ArtistPick(
                          name: name,
                          followed: _followedNames.contains(name),
                          onTap: () =>
                              context.push('/artist/${Uri.encodeComponent(name)}'),
                          onFollow: () => _toggleFollow(name),
                        )),
                ],
              ),
            ),
          ],
          if (_genres.isNotEmpty) ...[
            FnSectionHead(
              title: '按流派探索',
              actionLabel: '全部',
              onAction: () => context.push('/library?tab=genres'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      fnGridCols(context, mobile: 2, laptop: 4, desktop: 6),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  mainAxisExtent: fnGenreTileHeight(context),
                ),
                itemCount: _genres.take(fnBpOf(context).isWide ? 12 : 6).length,
                itemBuilder: (context, i) {
                  final g = _genres[i];
                  return FnGenreTile(
                    name: g.name,
                    count: g.songCount,
                    onTap: () =>
                        context.push('/genre/${Uri.encodeComponent(g.name)}'),
                  );
                },
              ),
            ),
          ],
          if (_albums.isNotEmpty) ...[
            FnSectionHead(
              title: '新进专辑',
              actionLabel: '曲库',
              onAction: () => context.push('/library?tab=albums'),
            ),
            SizedBox(
              height: 208,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                itemCount: _albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final a = _albums[i];
                  final id = a.id ?? 0;
                  return SizedBox(
                    width: 150,
                    child: FnAlbumCell(
                      albumId: id,
                      name: a.name,
                      artist: a.subtitle ?? '',
                      onTap: () => _openAlbum(a),
                    ),
                  );
                },
              ),
            ),
          ],
          FnPageFoot(
            left: '已同步 ${_songs.length} 首 · 每日 ${_daily.length} 首推荐',
            right: '同步设置',
            onRight: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Set<String> get _followedNames => _artists.map((a) => a.name).toSet();

  List<String> _uniqueArtists() {
    final seen = <String>{};
    final out = <String>[];
    for (final s in _songs) {
      if (s.artist.isNotEmpty && seen.add(s.artist)) out.add(s.artist);
    }
    return out;
  }

  Future<void> _toggleFollow(String name) async {
    final on = _followedNames.contains(name);
    try {
      if (on) {
        await ApiClient.instance.unfollowArtist(name);
      } else {
        await ApiClient.instance.followArtist(name);
      }
      await _load();
      if (mounted) fnToast(context, on ? '已取消关注 $name' : '已关注 $name');
    } catch (e) {
      if (mounted) fnToast(context, '操作失败：$e');
    }
  }

  void _openAlbum(AggregateItem a) {
    context.push(
        '/album/${a.id ?? 0}?artist=${Uri.encodeComponent(a.subtitle ?? '')}&title=${Uri.encodeComponent(a.name)}');
  }
}

/// 快捷入口卡（design/v3 css/pages/discover.css `.quick-card`：图标 38 + 两行文案）。
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: FnColors.surface,
          borderRadius: BorderRadius.circular(FnRadius.md),
          border: Border.all(color: FnColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: FnColors.limeSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: FnColors.limeText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 显式行高：卡片内容区只有 38（66 - 上下 14），
                  // 沿用主题字号行高会在 1px 处溢出。
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: FnColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({
    required this.songs,
    required this.day,
    required this.month,
    required this.weekday,
    required this.onPlay,
  });

  final List<Song> songs;
  final int day;
  final int month;
  final String weekday;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    final laptop = bp == FnBp.laptop;
    final coverId = songs.isEmpty ? 1 : songs.first.id;
    final hue = fnHue(coverId).toDouble();
    final artSize = mobile ? const Size(108, 74) : const Size(240, 170);
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 6, kFnPad, 0),
      height: mobile ? 248 : (laptop ? 224 : 244),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(mobile ? FnRadius.md : FnRadius.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF14171D), Color(0xFF0B0D10)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.84, -1),
                  radius: 1.1,
                  colors: [
                    HSLColor.fromAHSL(0.5, hue, 0.68, 0.46).toColor(),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1, 1),
                  radius: 0.9,
                  colors: [
                    HSLColor.fromAHSL(0.45, (hue + 40) % 360, 0.58, 0.3)
                        .toColor(),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.66],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 20 : (laptop ? 28 : 32),
              mobile ? 18 : (laptop ? 26 : 30),
              mobile ? 20 : (laptop ? 28 : 32),
              mobile ? 18 : (laptop ? 26 : 30),
            ),
            child: mobile
                ? Stack(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 212),
                        child: _copy(context, mobile: true),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: _stack(context, artSize, mobile: true),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _copy(context, mobile: false)),
                      SizedBox(
                        width: laptop ? 240 : 300,
                        child: Center(
                          child: Transform.scale(
                            scale: laptop ? 0.86 : 1,
                            child: _stack(context, artSize, mobile: false),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _copy(BuildContext context, {required bool mobile}) {
    const dp = fnDarkPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              day.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: mobile ? 46 : (fnBpOf(context) == FnBp.laptop ? 60 : 72),
                height: 0.95,
                fontWeight: FontWeight.w800,
                letterSpacing: -3,
                color: dp.lime,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${month.toString().padLeft(2, '0')} 月 · $weekday',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.48,
                fontFamily: FnText.monoFamily.first,
                color: Colors.white.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
        SizedBox(height: mobile ? 10 : 16),
        Text(
          '每日推荐 · ${songs.length} 首',
          style: TextStyle(
            fontSize: mobile ? 19 : 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.44,
            color: const Color(0xFFF5F7FA),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '根据你最近循环的口味生成',
          style: TextStyle(
            fontSize: mobile ? 11.5 : 12,
            color: Colors.white.withValues(alpha: 0.56),
          ),
        ),
        if (!mobile) const Spacer() else const SizedBox(height: 16),
        GestureDetector(
          onTap: onPlay,
          child: Container(
            height: mobile ? 38 : 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: dp.lime,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 18, color: dp.limeInk),
                const SizedBox(width: 6),
                Text(
                  '播放全部',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: dp.limeInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stack(BuildContext context, Size size, {required bool mobile}) {
    final count = songs.length.clamp(0, 3);
    final base = mobile ? 52.0 : 118.0;
    final mid = mobile ? 62.0 : 132.0;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: mobile
                  ? (i == 0 ? 0 : (i == 1 ? 26 : 56))
                  : (i == 0 ? 0 : (i == 1 ? 60 : 128)),
              top: mobile
                  ? (i == 0 ? 16 : (i == 1 ? 2 : 18))
                  : (i == 0 ? 26 : (i == 1 ? 4 : 32)),
              child: Transform.rotate(
                angle: (i == 0 ? -9 : (i == 1 ? 4 : 11)) * 3.14159 / 180,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(mobile ? 9 : 14),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: mobile ? 22 : 40,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: FnCover(
                    songId: songs[i].id,
                    size: i == 1 ? mid : base,
                    radius: mobile ? 9 : 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoamCard extends StatelessWidget {
  const _RoamCard({
    required this.title,
    required this.sub,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String sub;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 158,
        height: 118,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FnRadius.md),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [...colors, FnColors.surface],
            stops: const [0, 0.62, 1],
          ),
          border: Border.all(color: FnColors.line2),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Icon(icon, size: 17, color: FnColors.lime),
                ),
                const Spacer(),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 10, color: FnColors.textSecondary)),
              ],
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Icon(CupertinoIcons.chevron_forward,
                  size: 15, color: FnColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistPick extends StatelessWidget {
  const _ArtistPick({
    required this.name,
    required this.followed,
    required this.onTap,
    this.onFollow,
  });

  final String name;
  final bool followed;
  final VoidCallback onTap;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final avatar = switch (fnBpOf(context)) {
      FnBp.mobile => 72.0,
      FnBp.laptop => 84.0,
      FnBp.desktop => 96.0,
    };
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: avatar + 16,
        child: Column(
          children: [
            SizedBox(
              width: avatar,
              height: avatar,
              child: Stack(
                children: [
                  FnArtistAvatar(name: name, size: avatar),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: onFollow,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: followed
                              ? FnColors.lime
                              : FnColors.surface3,
                          shape: BoxShape.circle,
                          border: Border.all(color: FnColors.base, width: 2),
                        ),
                        child: Icon(
                          followed ? Icons.check_rounded : Icons.add_rounded,
                          size: 10,
                          color: followed
                              ? FnColors.limeInk
                              : FnColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: FnColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

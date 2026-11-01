import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';
import '../widgets/track_menu_sheet.dart';

/// 流派详情：渐变 hero + 热门曲目 + 代表专辑 + 艺人 + 其他流派。
class GenrePage extends StatefulWidget {
  const GenrePage({super.key, required this.name});

  final String name;

  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  static const _descs = {
    '华语流行': '旋律优先，情绪直给。这里收着你最常循环的那批中文歌。',
    '独立摇滚': '吉他与夜色，失真里藏着一点温柔。',
    '电影原声': '把画面留在耳朵里，适合独自走一段路。',
    '电子': '合成器、低频和一点点未来感。',
    '爵士': '即兴、呼吸与铜管的温度。',
    '民谣': '一把吉他，一段故事，房间里的回声。',
  };

  bool _loading = true;
  String? _error;
  List<Song> _songs = const [];
  List<AggregateItem> _albums = const [];
  List<AggregateItem> _artists = const [];
  List<GenreInfo> _genres = const [];
  Set<int> _favIds = <int>{};
  Set<String> _followNames = <String>{};

  int get _hue => (widget.name.hashCode.abs() * 37) % 360;

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
        ApiClient.instance.fetchGenreDetail(widget.name),
        ApiClient.instance.fetchGenres(),
        ApiClient.instance.fetchAggregate(by: 'album', pageSize: 200),
        ApiClient.instance.fetchAggregate(by: 'artist', pageSize: 300),
        ApiClient.instance.fetchFavorites(),
        ApiClient.instance.fetchFollowedArtists(),
      ]);
      final detail = res[0] as GenreDetail;
      final songs = detail.songs;
      final genres = res[1] as List<GenreInfo>;
      final albumItems = (res[2] as AggregatePage).items;
      final artistItems = (res[3] as AggregatePage).items;
      final favs = res[4] as List<Song>;
      final followed = res[5] as List<FollowedArtist>;

      final albumNames =
          songs.map((s) => s.album).where((n) => n.isNotEmpty).toSet();
      final artistNames = songs.map((s) => s.artist).toSet();

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _genres = genres;
        _albums = albumItems.where((a) => albumNames.contains(a.name)).toList();
        if (_albums.isEmpty) _albums = albumItems.take(3).toList();
        _artists =
            artistItems.where((a) => artistNames.contains(a.name)).toList();
        if (_artists.isEmpty) _artists = artistItems.take(3).toList();
        _favIds = favs.map((s) => s.id).toSet();
        _followNames = followed.map((a) => a.name).toSet();
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

  int get _totalCount {
    for (final g in _genres) {
      if (g.name == widget.name) return g.songCount;
    }
    return _songs.length;
  }

  void _play(bool shuffle) {
    if (_songs.isEmpty) return;
    final pool = [..._songs];
    if (shuffle) pool.shuffle();
    PlayerController.instance.playList(pool, 0);
    if (shuffle) {
      fnToast(context, '随机播放 ${widget.name}',
          icon: Icons.shuffle_rounded);
    }
  }

  Future<void> _toggleFollow(String name) async {
    final on = _followNames.contains(name);
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

  /// design/v3 genre.js `#g-more`：全部加入队列 / 按音质筛选。
  /// 下载该流派、分享流派在原型里只是 toast，后端也无对应能力，故不给出假入口。
  void _more() {
    showFnSheet<void>(
      context,
      eyebrow: 'GENRE',
      title: widget.name,
      subtitle: '$_totalCount 首作品',
      children: [
        FnOptionRow(
          title: '全部加入队列',
          subtitle: '${_songs.length} 首',
          icon: Icons.playlist_add_rounded,
          onTap: () {
            Navigator.pop(context);
            for (final s in _songs) {
              PlayerController.instance.playNext(s);
            }
            fnToast(context, '已加入 ${_songs.length} 首',
                icon: Icons.playlist_add_rounded);
          },
        ),
        FnOptionRow(
          title: '按音质筛选',
          icon: Icons.high_quality_rounded,
          onTap: () {
            Navigator.pop(context);
            context.push('/songs');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      title: '流派加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _hero(),
                      FnSectionHead(
                        title: '代表曲目',
                        sub: _totalCount > _songs.length
                            ? '${_songs.length} 首 · 曲库共 $_totalCount TRACKS'
                            : '${_songs.length} 首 TRACKS',
                      ),
                      if (fnBpOf(context) == FnBp.desktop)
                        FnSongTable(
                          songs: _songs,
                          favoriteIds: _favIds,
                          currentId: PlayerController.instance.current?.id,
                          isPlaying: PlayerController.instance.isPlaying,
                          onPlay: (i) {
                            PlayerController.instance.playList(_songs, i);
                          },
                          onMore: (i) => showTrackMenu(
                            context,
                            _songs[i],
                            isFavorite: _favIds.contains(_songs[i].id),
                            onFavoriteChanged: () => _load(),
                          ),
                        )
                      else
                        for (var i = 0; i < _songs.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: kFnPad - 8),
                            child: FnSongRow(
                              song: _songs[i],
                              ord: (i + 1).toString(),
                              isCurrent:
                                  PlayerController.instance.current?.id ==
                                      _songs[i].id,
                              isPlaying: PlayerController.instance.isPlaying,
                              subtitle:
                                  '${_songs[i].artist} · ${_songs[i].album}',
                              onTap: () {
                                PlayerController.instance.playList(_songs, i);
                              },
                              onMore: () => showTrackMenu(
                                context,
                                _songs[i],
                                isFavorite: _favIds.contains(_songs[i].id),
                                onFavoriteChanged: () => _load(),
                              ),
                            ),
                          ),
                      if (_songs.isEmpty)
                        const FnEmpty(
                          icon: CupertinoIcons.music_note_2,
                          title: '这个流派还没有歌曲',
                          compact: true,
                        ),
                      if (_albums.isNotEmpty) ...[
                        const FnSectionHead(
                            title: '代表专辑', sub: 'FROM THIS GENRE'),
                        // design/v3 components.css `.grid-cards`：2 / 3 / auto-fill(180)。
                        _albumGrid(),
                      ],
                      if (_artists.isNotEmpty) ...[
                        FnSectionHead(
                            title: '代表艺人', sub: '${_artists.length} 位'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                          child: Column(
                            children: [
                              for (final a in _artists)
                                _artistRow(a),
                            ],
                          ),
                        ),
                      ],
                      FnSectionHead(
                        title: '其他流派',
                        actionLabel: '全部',
                        onAction: () => context.go('/library'),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: fnGridCols(context,
                                mobile: 2, laptop: 3, desktop: 4),
                            mainAxisSpacing: 9,
                            crossAxisSpacing: 9,
                            mainAxisExtent: fnGenreTileHeight(context),
                          ),
                          itemCount:
                              _genres.where((g) => g.name != widget.name).length,
                          itemBuilder: (context, i) {
                            final list = _genres
                                .where((g) => g.name != widget.name)
                                .toList();
                            final g = list[i];
                            return FnGenreTile(
                              name: g.name,
                              count: g.songCount,
                              onTap: () => context.push(
                                  '/genre/${Uri.encodeComponent(g.name)}'),
                            );
                          },
                        ),
                      ),
                      FnPageFoot(
                        left: '${widget.name} · INDEXED',
                        right: '重新索引',
                        onRight: () => context.push('/scan'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _hero() {
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    // design/v3 css/pages/genre.css：desktop min 240 / laptop 200 / mobile 无下限；
    // 标题 40 / 32 / 30；内边距 64/30/26 · 56/24/22 · 56/20/20。
    final minHeight = switch (bp) {
      FnBp.mobile => 0.0,
      FnBp.laptop => 200.0,
      FnBp.desktop => 240.0,
    };
    final titleSize = switch (bp) {
      FnBp.mobile => 30.0,
      FnBp.laptop => 32.0,
      FnBp.desktop => 40.0,
    };
    final (padH, padT, padB) = switch (bp) {
      FnBp.mobile => (20.0, 56.0, 20.0),
      FnBp.laptop => (24.0, 56.0, 22.0),
      FnBp.desktop => (30.0, 64.0, 26.0),
    };
    return Container(
      margin: EdgeInsets.fromLTRB(kFnPad, mobile ? 8 : 16, kFnPad, 4),
      padding: EdgeInsets.fromLTRB(padH, padT, padH, padB),
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FnRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, _hue.toDouble(), 0.72, 0.52)
                .toColor()
                .withValues(alpha: 0.92),
            HSLColor.fromAHSL(1, _hue.toDouble(), 0.58, 0.28)
                .toColor()
                .withValues(alpha: 0.94),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 强制深色：亮色系流派（黄/青等）在浅色主题下也要保证白字对比度。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FnRadius.lg),
                color: Colors.black.withValues(alpha: 0.32),
              ),
            ),
          ),
          Positioned(
            right: mobile ? 16 : 22,
            top: mobile ? 16 : 22,
            child: SizedBox(
              height: mobile ? 30 : 36,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in const [12, 20, 9, 26, 16, 30, 11, 22, 8, 18, 13, 24])
                    Container(
                      width: 3,
                      height: mobile ? h * 0.84 : h.toDouble(),
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // design/v3 genre.js `.g-back`：浮于 hero 左上（三档都在）。
          Positioned(
            left: 16,
            top: 16,
            child: FnIconBtn(
              icon: CupertinoIcons.chevron_back,
              variant: FnIconBtnVariant.dark,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'GENRE · SELF-HOSTED INDEX',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.5,
                  fontFamily: FnText.monoFamily.first,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: titleSize,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _descs[widget.name] ?? '从你的曲库里挑出的同风格作品。',
                style: TextStyle(
                  fontSize: mobile ? 11.5 : 12.5,
                  height: mobile ? 1.55 : 1.6,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: mobile ? 13 : 15),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _meta('$_totalCount 首', mobile),
                  _sep(),
                  _meta('${_artists.length} 位艺人', mobile),
                  _sep(),
                  _meta('LOSSLESS 优先', mobile),
                  _sep(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSLColor.fromAHSL(
                                  1, _hue.toDouble(), 0.72, 0.55)
                              .toColor(),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.5),
                              spreadRadius: 1.5,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      _meta('HUE $_hue', mobile),
                    ],
                  ),
                ],
              ),
              SizedBox(height: mobile ? 16 : 20),
              // design/v3 genre.js `.g-actions`：播放 / 随机播放 / 更多。
              _heroActions(mobile: mobile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroActions({required bool mobile}) {
    final play = FnButton(
      label: '播放',
      icon: Icons.play_arrow_rounded,
      size: FnButtonSize.sm,
      dark: true,
      block: mobile,
      onTap: () => _play(false),
    );
    final shuffle = FnButton(
      label: '随机播放',
      icon: Icons.shuffle_rounded,
      variant: FnButtonVariant.soft,
      size: FnButtonSize.sm,
      dark: true,
      block: mobile,
      onTap: () => _play(true),
    );
    final more = FnIconBtn(
      icon: Icons.more_horiz,
      variant: FnIconBtnVariant.dark,
      onTap: _more,
    );
    if (!mobile) {
      return Row(
        children: [
          play,
          const SizedBox(width: 10),
          shuffle,
          const SizedBox(width: 10),
          more,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: play),
        const SizedBox(width: 10),
        Expanded(child: shuffle),
        const SizedBox(width: 10),
        more,
      ],
    );
  }

  Widget _meta(String text, bool mobile) => Text(
        text,
        style: TextStyle(
          fontSize: mobile ? 9 : 10,
          letterSpacing: 0.4,
          fontFamily: FnText.monoFamily.first,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      );

  Widget _sep() => Container(
        width: 1,
        height: 8,
        color: Colors.white.withValues(alpha: 0.34),
      );

  /// design/v3 components.css `.grid-cards`：mobile 2 / laptop 3 / desktop auto-fill(180)。
  Widget _albumGrid() {
    final bp = fnBpOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kFnPad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          const minCol = 180.0;
          final cols = switch (bp) {
            FnBp.mobile => 2,
            FnBp.laptop => 3,
            FnBp.desktop => ((constraints.maxWidth + gap) / (minCol + gap))
                .floor()
                .clamp(2, 8),
          };
          final cell = (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: 16,
            children: [
              for (final a in _albums)
                SizedBox(
                  width: cell,
                  child: FnAlbumCell(
                    albumId: a.id ?? 0,
                    name: a.name,
                    artist: a.subtitle ?? '',
                    onTap: () => context.push(
                        '/album/${a.id ?? 0}?artist=${Uri.encodeComponent(a.subtitle ?? '')}&title=${Uri.encodeComponent(a.name)}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _artistRow(AggregateItem a) {
    final followed = _followNames.contains(a.name);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/artist/${Uri.encodeComponent(a.name)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            FnArtistAvatar(name: a.name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${a.songCount} 首 · ${widget.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: FnColors.textSecondary)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _toggleFollow(a.name),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: followed ? FnColors.limeSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: followed ? FnColors.lime : FnColors.line2),
                ),
                child: Row(
                  children: [
                    Icon(followed ? Icons.check_rounded : Icons.add_rounded,
                        size: 13,
                        color:
                            followed ? FnColors.lime : FnColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(followed ? '已关注' : '关注',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: followed
                                ? FnColors.lime
                                : FnColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

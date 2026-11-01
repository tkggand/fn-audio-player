import 'dart:ui' show ImageFilter;

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

/// 艺人：头像 hero + 随机/关注 + 热门歌曲 + 专辑 + 相似艺人 + 简介。
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.name});

  final String name;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  ArtistDetail? _artist;
  List<AggregateItem> _similar = const [];
  Set<int> _favIds = <int>{};
  bool _loading = true;
  String? _error;

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
        ApiClient.instance.fetchArtistDetail(widget.name),
        ApiClient.instance.fetchFavorites(),
        ApiClient.instance.fetchAggregate(by: 'artist', pageSize: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _artist = res[0] as ArtistDetail;
        _favIds = (res[1] as List<Song>).map((s) => s.id).toSet();
        _similar = (res[2] as AggregatePage)
            .items
            .where((a) => a.name != widget.name)
            .take(6)
            .toList();
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

  /// design/v3 artist.js `#ar-more`：随机播放 / 热门歌曲加入队列。
  /// 分享、下载、编辑元数据后端无对应能力，故不给出假入口。
  void _moreSheet() {
    final songs = _artist?.songs ?? const <Song>[];
    final top = songs.take(10).toList();
    showFnSheet<void>(
      context,
      eyebrow: 'ARTIST',
      title: widget.name,
      subtitle: '${_artist?.songCount ?? songs.length} 首作品',
      children: [
        FnOptionRow(
          title: '随机播放',
          icon: Icons.shuffle_rounded,
          onTap: () {
            Navigator.pop(context);
            if (songs.isEmpty) return;
            final pool = [...songs]..shuffle();
            if (!PlayerController.instance.shuffle) {
              PlayerController.instance.toggleShuffle();
            }
            PlayerController.instance.playList(pool, 0);
            fnToast(context, '随机播放 ${widget.name}');
          },
        ),
        FnOptionRow(
          title: '热门歌曲加入队列',
          subtitle: '${top.length} 首',
          icon: CupertinoIcons.add,
          onTap: () {
            Navigator.pop(context);
            for (final s in top) {
              PlayerController.instance.playNext(s);
            }
            if (top.isNotEmpty) fnToast(context, '已加入 ${top.length} 首');
          },
        ),
      ],
    );
  }

  /// design/v3 artist.js：eyebrow 为 `ARTIST · genre`。
  String _dominantGenre(List<Song> songs) {
    final counts = <String, int>{};
    for (final s in songs) {
      final g = s.genre?.trim() ?? '';
      if (g.isEmpty) continue;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    if (counts.isEmpty) return '本地曲库';
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.key;
  }

  Future<void> _toggleFollow() async {
    final on = _artist?.followed ?? false;
    try {
      if (on) {
        await ApiClient.instance.unfollowArtist(widget.name);
      } else {
        await ApiClient.instance.followArtist(widget.name);
      }
      await _load();
      if (mounted) {
        fnToast(context, on ? '已取消关注 ${widget.name}' : '已关注 ${widget.name}');
      }
    } catch (e) {
      if (mounted) fnToast(context, '操作失败：$e');
    }
  }

  Future<void> _toggleFav(Song song) async {
    final on = _favIds.contains(song.id);
    try {
      if (on) {
        await ApiClient.instance.removeFavorite(song.id);
      } else {
        await ApiClient.instance.addFavorite(song.id);
      }
      await _load();
      if (mounted) fnToast(context, on ? '已取消收藏' : '已收藏');
    } catch (e) {
      if (mounted) fnToast(context, '操作失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = _artist;
    final songs = artist?.songs ?? const <Song>[];
    // 按专辑归组（取专辑内第一首作为封面种子）。
    final albums = <String, Song>{};
    for (final s in songs) {
      albums.putIfAbsent(s.album, () => s);
    }
    final coverId = songs.isEmpty ? 1 : songs.first.id;
    final wide = fnBpOf(context).isWide;
    final topSongs = songs.take(fnBpOf(context) == FnBp.desktop ? 10 : 6).toList();
    // design/v3 artist.js eyebrow：`ARTIST · genre`（取作品里出现最多的流派）。
    final genre = _dominantGenre(songs);
    return Scaffold(
      backgroundColor: FnColors.base,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: FnEmpty(
                    icon: CupertinoIcons.exclamationmark_circle,
                    title: '艺人加载失败',
                    message: _error,
                    actionLabel: '重试',
                    onAction: _load,
                  ),
                )
              : ListView(
                  padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _Hero(
                      name: widget.name,
                      coverId: coverId,
                      songCount: artist?.songCount ?? 0,
                      albumCount: artist?.albumCount ?? albums.length,
                      genre: genre,
                      followed: artist?.followed == true,
                      onPlay: () {
                        if (songs.isEmpty) return;
                        PlayerController.instance.playList(songs, 0);
                      },
                      onFollow: _toggleFollow,
                      onMore: _moreSheet,
                    ),
                    FnSectionHead(
                      title: '热门歌曲',
                      sub: '${songs.length} 首',
                      actionLabel: '全部',
                      onAction: () => context.push('/songs'),
                    ),
                    if (fnBpOf(context) == FnBp.desktop)
                      FnSongTable(
                        songs: topSongs,
                        favoriteIds: _favIds,
                        currentId: PlayerController.instance.current?.id,
                        isPlaying: PlayerController.instance.isPlaying,
                        onPlay: (i) {
                          PlayerController.instance.playList(songs, i);
                        },
                        onMore: (i) => showTrackMenu(
                          context,
                          songs[i],
                          isFavorite: _favIds.contains(songs[i].id),
                          onFavoriteChanged: () => _toggleFav(songs[i]),
                        ),
                        onFavorite: (i) => _toggleFav(songs[i]),
                      )
                    else
                      for (var i = 0; i < topSongs.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: kFnPad - 8),
                          child: FnSongRow(
                            song: topSongs[i],
                            ord: (i + 1).toString(),
                            isCurrent: PlayerController.instance.current?.id ==
                                topSongs[i].id,
                            isPlaying: PlayerController.instance.isPlaying,
                            onTap: () {
                              PlayerController.instance.playList(songs, i);
                            },
                            onMore: () => showTrackMenu(
                              context,
                              topSongs[i],
                              isFavorite: _favIds.contains(topSongs[i].id),
                              onFavoriteChanged: () => _toggleFav(topSongs[i]),
                            ),
                          ),
                        ),
                    if (songs.length > topSongs.length)
                      Padding(
                        padding:
                            EdgeInsets.fromLTRB(fnPagePad(context), 10, fnPagePad(context), 0),
                        child: FnButton(
                          label: '查看全部 ${songs.length} 首',
                          variant: FnButtonVariant.soft,
                          size: FnButtonSize.sm,
                          block: true,
                          onTap: () => context.push('/songs'),
                        ),
                      ),
                    FnSectionHead(
                      title: '专辑',
                      sub: '${albums.length} 张',
                    ),
                    if (wide)
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: fnPagePad(context)),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: fnGridCols(context,
                                mobile: 2, laptop: 4, desktop: 6),
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: albums.length,
                          itemBuilder: (context, i) {
                            final e = albums.entries.elementAt(i);
                            final s = e.value;
                            return FnAlbumCell(
                              albumId: s.id,
                              name: e.key,
                              artist: widget.name,
                              year: s.year,
                              onTap: () => context.push(
                                  '/album/${s.id}?artist=${Uri.encodeComponent(widget.name)}&title=${Uri.encodeComponent(e.key)}&cover=${s.id}'),
                            );
                          },
                        ),
                      )
                    else
                      SizedBox(
                        height: 208,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                              horizontal: fnPagePad(context)),
                          itemCount: albums.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final e = albums.entries.elementAt(i);
                            final s = e.value;
                            return SizedBox(
                              width: 150,
                              child: FnAlbumCell(
                                albumId: s.id,
                                name: e.key,
                                artist: widget.name,
                                year: s.year,
                                onTap: () => context.push(
                                    '/album/${s.id}?artist=${Uri.encodeComponent(widget.name)}&title=${Uri.encodeComponent(e.key)}&cover=${s.id}'),
                              ),
                            );
                          },
                        ),
                      ),
                    if (_similar.isNotEmpty) ...[
                      const FnSectionHead(title: '相似艺人', sub: '同一种声音'),
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: fnPagePad(context)),
                        child: Column(
                          children: [
                            for (final a in _similar)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => context.push(
                                    '/artist/${Uri.encodeComponent(a.name)}'),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  child: Row(
                                    children: [
                                      FnArtistAvatar(name: a.name, size: 42),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(a.name,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                            Text(
                                              '${a.songCount} 首 · ${a.albumCount} 张专辑',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: FnColors
                                                      .textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(CupertinoIcons.chevron_forward,
                                          size: 15,
                                          color: FnColors.textTertiary),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const FnSectionHead(title: '简介', sub: 'BIOGRAPHY'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: FnColors.surface,
                          borderRadius: BorderRadius.circular(FnRadius.md),
                          border: Border.all(color: FnColors.line),
                        ),
                        child: Text(
                          '${widget.name} 的作品已收录 ${artist?.songCount ?? 0} 首、'
                          '${artist?.albumCount ?? albums.length} 张专辑。'
                          '本地元数据来自 NAS 曲库，暂未接入在线艺人简介。',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.65,
                            color: FnColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const FnPageFoot(
                        left: 'SELF-HOSTED METADATA', right: '元数据来源'),
                  ],
                ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.coverId,
    required this.songCount,
    required this.albumCount,
    required this.genre,
    required this.followed,
    required this.onPlay,
    required this.onFollow,
    required this.onMore,
  });

  final String name;
  final int coverId;
  final int songCount;
  final int albumCount;
  final String genre;
  final bool followed;
  final VoidCallback onPlay;
  final VoidCallback onFollow;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final hue = (name.hashCode.abs() * 47) % 360;
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    // design/v3 css/pages/artist.css：头像 180（desktop）/ 150（laptop）/ 120（mobile），
    // mobile 纵向居中堆叠。
    final avatarSize = switch (bp) {
      FnBp.mobile => 120.0,
      FnBp.laptop => 150.0,
      FnBp.desktop => 180.0,
    };
    return SizedBox(
      height: mobile ? 380 : (bp.isWide ? 388 : 356),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
            child: Transform.scale(
              scale: 1.2,
              child: Image.network(
                ApiClient.instance.coverUrl(coverId),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => DecoratedBox(
                    decoration: BoxDecoration(gradient: fnCoverGradient(coverId))),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  FnColors.base.withValues(alpha: 0.32),
                  FnColors.base.withValues(alpha: FnColors.isDark ? 0.84 : 0.92),
                  FnColors.base,
                ],
                stops: const [0, 0.76, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.6),
                radius: 0.75,
                colors: [
                  HSLColor.fromAHSL(FnColors.isDark ? 0.2 : 0.16, hue.toDouble(), 0.6, 0.45)
                      .toColor(),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 12,
            right: 12,
            child: Row(
              children: [
                FnIconBtn(
                  icon: CupertinoIcons.chevron_back,
                  variant: FnColors.isDark
                      ? FnIconBtnVariant.dark
                      : FnIconBtnVariant.glass,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                FnIconBtn(
                  icon: Icons.more_horiz,
                  variant: FnColors.isDark
                      ? FnIconBtnVariant.dark
                      : FnIconBtnVariant.glass,
                  onTap: onMore,
                ),
              ],
            ),
          ),
          Positioned(
            left: fnPagePad(context),
            right: fnPagePad(context),
            bottom: 20,
            child: Column(
              crossAxisAlignment:
                  mobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (mobile) ...[
                  FnArtistAvatar(name: name, size: avatarSize),
                  const SizedBox(height: 16),
                  _artistIdentity(center: true),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FnArtistAvatar(name: name, size: avatarSize),
                      const SizedBox(width: 28),
                      Expanded(child: _artistIdentity(center: false)),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Num(value: '$songCount', label: '曲目'),
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: FnColors.line2,
                    ),
                    _Num(value: '$albumCount', label: '专辑'),
                    if (!mobile) const Spacer() else const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FnColors.glassLight,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: FnColors.line2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                                color: FnColors.primary,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '已同步',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: FnColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // design/v3 artist.js `.ar-actions`：播放热门 / 关注 / 更多。
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: mobile ? WrapAlignment.center : WrapAlignment.start,
                  children: [
                    FnButton(
                      label: '播放热门',
                      icon: Icons.play_arrow_rounded,
                      size: FnButtonSize.sm,
                      onTap: onPlay,
                    ),
                    FnButton(
                      label: followed ? '已关注' : '关注',
                      icon: followed
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      variant: FnButtonVariant.soft,
                      size: FnButtonSize.sm,
                      onTap: onFollow,
                    ),
                    FnButton(
                      label: '更多',
                      icon: Icons.more_horiz,
                      variant: FnButtonVariant.soft,
                      size: FnButtonSize.sm,
                      onTap: onMore,
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

  Widget _artistIdentity({required bool center}) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'ARTIST · $genre',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.44,
            color: FnColors.limeText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          maxLines: 2,
          textAlign: center ? TextAlign.center : TextAlign.start,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: center ? 26 : 34,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: FnColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: FnColors.textPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            color: FnColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

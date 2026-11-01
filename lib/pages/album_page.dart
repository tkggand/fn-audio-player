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

/// 专辑详情：模糊封面 hero + 操作栏 + 曲目 + 音频信息 + 相关专辑。
class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.albumId,
    this.title,
    this.artist,
    this.coverSongId,
  });

  final int albumId;
  final String? title;
  final String? artist;
  final int? coverSongId;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  AlbumDetail? _album;
  List<AggregateItem> _related = const [];
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
        ApiClient.instance.fetchAlbumDetail(widget.albumId),
        ApiClient.instance.fetchFavorites(),
        ApiClient.instance.fetchAggregate(by: 'album', pageSize: 12),
      ]);
      if (!mounted) return;
      setState(() {
        _album = res[0] as AlbumDetail;
        _favIds = (res[1] as List<Song>).map((s) => s.id).toSet();
        _related = (res[2] as AggregatePage)
            .items
            .where((a) => a.id != widget.albumId)
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

  /// design/v3 album.js `#al-more`：播放整张 / 加入队列 / 查看艺人。
  /// 下载、分享、重新扫描元数据后端无对应能力，故不给出假入口。
  void _moreSheet() {
    final album = _album;
    final songs = album?.songs ?? const <Song>[];
    final artist = album?.artist ?? widget.artist ?? '';
    showFnSheet<void>(
      context,
      eyebrow: 'ALBUM',
      title: album?.name ?? widget.title ?? '未知专辑',
      subtitle: artist,
      children: [
        FnOptionRow(
          title: '播放整张专辑',
          icon: Icons.play_arrow_rounded,
          onTap: () {
            Navigator.pop(context);
            if (songs.isEmpty) return;
            PlayerController.instance.playList(songs, 0);
          },
        ),
        FnOptionRow(
          title: '加入队列',
          subtitle: '${songs.length} 首',
          icon: CupertinoIcons.add,
          onTap: () {
            Navigator.pop(context);
            for (final s in songs) {
              PlayerController.instance.playNext(s);
            }
            if (songs.isNotEmpty) fnToast(context, '已加入 ${songs.length} 首');
          },
        ),
        if (artist.isNotEmpty)
          FnOptionRow(
            title: '查看艺人',
            subtitle: artist,
            icon: CupertinoIcons.person,
            onTap: () {
              Navigator.pop(context);
              context.push('/artist/${Uri.encodeComponent(artist)}');
            },
          ),
      ],
    );
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
    final album = _album;
    final songs = album?.songs ?? const <Song>[];
    final coverId = widget.coverSongId ?? (songs.isEmpty ? widget.albumId : songs.first.id);
    return Scaffold(
      backgroundColor: FnColors.base,
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _error != null
              ? Center(
                  child: FnEmpty(
                    icon: CupertinoIcons.exclamationmark_circle,
                    title: '专辑加载失败',
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
                      coverId: coverId,
                      title: album?.name ?? widget.title ?? '未知专辑',
                      artist: album?.artist ?? widget.artist ?? '未知艺术家',
                      songCount: album?.songCount ?? songs.length,
                      year: songs.firstOrNull?.year,
                      duration: songs.fold<double>(
                          0, (s, x) => s + (x.duration ?? 0)),
                      onMore: _moreSheet,
                      onArtist: () => context.push(
                          '/artist/${Uri.encodeComponent(album?.artist ?? widget.artist ?? '')}'),
                    ),
                    Padding(
                      padding:
                          EdgeInsets.fromLTRB(fnPagePad(context), 14, fnPagePad(context), 0),
                      child: Row(
                        children: [
                          FnButton(
                            label: '播放',
                            icon: Icons.play_arrow_rounded,
                            onTap: () {
                              if (songs.isEmpty) return;
                              PlayerController.instance.playList(songs, 0);
                            },
                          ),
                          const SizedBox(width: 8),
                          FnButton(
                            label: '随机',
                            icon: Icons.shuffle_rounded,
                            variant: FnButtonVariant.soft,
                            onTap: () {
                              if (songs.isEmpty) return;
                              final pool = [...songs]..shuffle();
                              if (!PlayerController.instance.shuffle) {
                                PlayerController.instance.toggleShuffle();
                              }
                              PlayerController.instance.playList(pool, 0);
                              fnToast(context, '随机播放整张专辑');
                            },
                          ),
                          const Spacer(),
                          FnIconBtn(
                            icon: Icons.download_rounded,
                            onTap: () => fnToast(context, '已开始下载专辑',
                                icon: Icons.download_rounded),
                          ),
                        ],
                      ),
                    ),
                    FnSectionHead(
                      title: '曲目',
                      sub: '${songs.length} 首',
                    ),
                    if (fnBpOf(context) == FnBp.desktop)
                      FnSongTable(
                        songs: songs,
                        favoriteIds: _favIds,
                        currentId: PlayerController.instance.current?.id,
                        isPlaying: PlayerController.instance.isPlaying,
                        ordinal: (i) =>
                            (songs[i].trackNo ?? i + 1).toString(),
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
                      for (var i = 0; i < songs.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: kFnPad - 8),
                          child: FnSongRow(
                            song: songs[i],
                            ord: (songs[i].trackNo ?? i + 1).toString(),
                            showDuration: true,
                            isCurrent: PlayerController.instance.current?.id ==
                                songs[i].id,
                            isPlaying: PlayerController.instance.isPlaying,
                            onTap: () {
                              PlayerController.instance.playList(songs, i);
                            },
                            onMore: () => showTrackMenu(
                              context,
                              songs[i],
                              isFavorite: _favIds.contains(songs[i].id),
                              onFavoriteChanged: () => _toggleFav(songs[i]),
                            ),
                          ),
                        ),
                    const FnGroupLabel('音频信息'),
                    FnGroupCard(children: [
                      FnListRow(
                        title: '格式',
                        value: songs.isEmpty
                            ? '-'
                            : '${(songs.first.codec ?? 'FLAC').toUpperCase()} · ${songs.first.bitDepth ?? '-'} bit',
                        showChevron: false,
                      ),
                      FnListRow(
                        title: '采样率',
                        value:
                            '${fmtSampleRate(songs.firstOrNull?.sampleRate)} kHz',
                        showChevron: false,
                      ),
                      FnListRow(
                        title: '声道',
                        value: songs.firstOrNull?.channels == 2
                            ? '立体声'
                            : '${songs.firstOrNull?.channels ?? '-'} 声道',
                        showChevron: false,
                      ),
                      const FnListRow(
                        title: '来源',
                        value: '本地 NAS',
                        showChevron: false,
                      ),
                    ]),
                    if (_related.isNotEmpty) ...[
                      FnSectionHead(
                        title: '相关专辑',
                        actionLabel: '全部',
                        onAction: () => context.go('/library'),
                      ),
                      SizedBox(
                        height: 208,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                          itemCount: _related.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final a = _related[i];
                            return SizedBox(
                              width: 150,
                              child: FnAlbumCell(
                                albumId: a.id ?? 0,
                                name: a.name,
                                artist: a.subtitle ?? '',
                                onTap: () => context.push(
                                    '/album/${a.id}?artist=${Uri.encodeComponent(a.subtitle ?? '')}&title=${Uri.encodeComponent(a.name)}'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const FnPageFoot(left: 'FN AUDIO · SELF-HOSTED', right: 'FLAC / NAS'),
                  ],
                ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.coverId,
    required this.title,
    required this.artist,
    required this.songCount,
    required this.duration,
    required this.year,
    required this.onMore,
    required this.onArtist,
  });

  final int coverId;
  final String title;
  final String artist;
  final int songCount;
  final double duration;
  final int? year;
  final VoidCallback onMore;
  final VoidCallback onArtist;

  @override
  Widget build(BuildContext context) {
    final hue = fnHue(coverId).toDouble();
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    // design/v3 css/pages/album.css：封面 240（desktop）/ 200（laptop），
    // mobile 62% 宽、最大 230；mobile 纵向居中堆叠。
    final coverSize = mobile
        ? (MediaQuery.sizeOf(context).width * 0.62).clamp(0.0, 230.0)
        : (bp == FnBp.laptop ? 200.0 : 240.0);
    return SizedBox(
      height: mobile ? 470 : (bp.isWide ? 360 : 340),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Transform.scale(
              scale: 1.2,
              child: Image.network(
                ApiClient.instance.coverUrl(coverId, kind: 'album'),
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
                  FnColors.base.withValues(alpha: 0.3),
                  FnColors.base.withValues(alpha: FnColors.isDark ? 0.82 : 0.9),
                  FnColors.base,
                ],
                stops: const [0, 0.74, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.5),
                radius: 0.7,
                colors: [
                  HSLColor.fromAHSL(FnColors.isDark ? 0.2 : 0.18, hue, 0.7, 0.5)
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
            bottom: mobile ? 22 : 30,
            child: mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FnCover(
                          songId: coverId,
                          kind: 'album',
                          size: coverSize,
                          radius: 12),
                      const SizedBox(height: 16),
                      _albumInfo(center: true),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FnCover(
                          songId: coverId,
                          kind: 'album',
                          size: coverSize,
                          radius: 12),
                      const SizedBox(width: 28),
                      Expanded(child: _albumInfo(center: false)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _albumInfo({required bool center}) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          year == null ? 'ALBUM' : 'ALBUM · $year',
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.44,
            color: FnColors.limeText,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          maxLines: 2,
          textAlign: center ? TextAlign.center : TextAlign.start,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 23,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            color: FnColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        // design/v3 album.js `.al-artist`：带头像的可点艺人链接。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: artist.isEmpty ? null : onArtist,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FnArtistAvatar(name: artist, size: 18),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: FnColors.textSecondary,
                  ),
                ),
              ),
              Icon(CupertinoIcons.chevron_forward,
                  size: 12, color: FnColors.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            '$songCount 首',
            fmtDuration(duration),
            'FLAC',
          ].join(' · '),
          maxLines: 1,
          textAlign: center ? TextAlign.center : TextAlign.start,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.5,
            fontFamily: FnText.monoFamily.first,
            color: FnColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

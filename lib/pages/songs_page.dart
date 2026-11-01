import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';
import '../widgets/track_menu_sheet.dart';

/// 全部歌曲：排序 / 格式筛选 / 批量播放入口。
class SongsPage extends StatefulWidget {
  const SongsPage({super.key, this.query = ''});

  final String query;

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  bool _loading = true;
  String? _error;
  List<Song> _songs = const [];
  Set<int> _favIds = <int>{};
  String _sort = 'title';
  String _filter = 'all';

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
        ApiClient.instance.fetchFavorites(),
      ]);
      if (!mounted) return;
      setState(() {
        _songs = res[0] as List<Song>;
        _favIds = (res[1] as List<Song>).map((s) => s.id).toSet();
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

  List<Song> get _visible {
    var list = _songs;
    final q = widget.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((s) => '${s.title} ${s.artist} ${s.album} ${s.genre ?? ''}'
              .toLowerCase()
              .contains(q))
          .toList();
    }
    if (_filter == 'lossless') list = list.where((s) => !s.isLossy).toList();
    if (_filter == 'hires') {
      list = list.where((s) => s.isHiRes || s.isDsd).toList();
    }
    if (_filter == 'favorites') {
      list = list.where((s) => _favIds.contains(s.id)).toList();
    }
    final out = [...list];
    switch (_sort) {
      case 'artist':
        out.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case 'duration':
        out.sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
      case 'recent':
        out.sort((a, b) => b.id.compareTo(a.id));
      default:
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return out;
  }

  void _play(List<Song> list, bool shuffle) {
    if (list.isEmpty) return;
    final pool = shuffle ? ([...list]..shuffle()) : list;
    PlayerController.instance.playList(pool, 0);
    if (shuffle) {
      fnToast(
        context,
        '随机播放 ${pool.length} 首',
        icon: Icons.shuffle_rounded,
      );
    }
  }

  void _sortSheet() {
    final labels = {
      'title': ('标题', Icons.sort_rounded),
      'artist': ('艺人', CupertinoIcons.mic),
      'duration': ('时长', CupertinoIcons.clock),
      'recent': ('最近添加', CupertinoIcons.time),
    };
    showFnSheet<void>(
      context,
      eyebrow: 'SORT',
      title: '排序方式',
      children: [
        for (final e in labels.entries)
          FnOptionRow(
            title: e.value.$1,
            icon: e.value.$2,
            on: _sort == e.key,
            onTap: () {
              Navigator.pop(context);
              setState(() => _sort = e.key);
              fnToast(context, '已按${e.value.$1}排序');
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
    final list = _visible;
    final total = list.fold<double>(0, (sum, s) => sum + (s.duration ?? 0));
    final wide = fnBpOf(context).isWide;
    final title = widget.query.isEmpty ? '全部歌曲' : '搜索结果';
    return Scaffold(
      backgroundColor: FnColors.base,
      body: Column(
        children: [
          if (wide)
            FnPageHead(
              eyebrow: 'SONGS',
              title: title,
              subtitle: widget.query.isEmpty
                  ? '${list.length} 首 · ${fmtDuration(total)}'
                  : '匹配「${widget.query}」· ${list.length} 首',
            )
          else
            FnNav(
              title: title,
              subtitle: widget.query.isEmpty
                  ? '${list.length} TRACKS'
                  : widget.query.toUpperCase(),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: FnEmpty(
                          icon: CupertinoIcons.exclamationmark_circle,
                          title: '加载失败',
                          message: _error,
                          actionLabel: '重试',
                          onAction: _load,
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.only(
                            bottom: fnBottomGapOf(context)),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                fnPagePad(context), 14, fnPagePad(context), 12),
                            child: Row(
                              children: [
                                FnButton(
                                  label: '播放全部',
                                  icon: Icons.play_arrow_rounded,
                                  onTap: () => _play(list, false),
                                  size: FnButtonSize.sm,
                                ),
                                const SizedBox(width: 8),
                                FnButton(
                                  label: '随机',
                                  icon: Icons.shuffle_rounded,
                                  variant: FnButtonVariant.soft,
                                  onTap: () => _play(list, true),
                                  size: FnButtonSize.sm,
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _sortSheet,
                                  child: Container(
                                    height: 34,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 11),
                                    decoration: BoxDecoration(
                                      color: FnColors.glassLight,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      border:
                                          Border.all(color: FnColors.line),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.sort_rounded,
                                            size: 15,
                                            color: FnColors.textSecondary),
                                        const SizedBox(width: 5),
                                        Text(
                                          switch (_sort) {
                                            'artist' => '艺人',
                                            'duration' => '时长',
                                            'recent' => '最近添加',
                                            _ => '标题',
                                          },
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color:
                                                  FnColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.symmetric(
                                  horizontal: fnPagePad(context)),
                              children: [
                                for (final f in const [
                                  ('all', '全部'),
                                  ('lossless', '无损以上'),
                                  ('hires', 'Hi-Res / DSD'),
                                  ('favorites', '已收藏'),
                                ]) ...[
                                  FnChip(
                                    label: f.$2,
                                    selected: _filter == f.$1,
                                    onTap: () =>
                                        setState(() => _filter = f.$1),
                                    small: true,
                                  ),
                                  const SizedBox(width: 7),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                fnPagePad(context), 10, fnPagePad(context), 6),
                            child: Row(
                              children: [
                                Icon(Icons.dns_rounded,
                                    size: 12,
                                    color: FnColors.textTertiary),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    '${list.length} 首 · ${fmtDuration(total)} · '
                                    '${widget.query.isEmpty ? '本地与 NAS 合并视图' : '匹配「${widget.query}」'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: FnColors.textTertiary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (list.isEmpty)
                            FnEmpty(
                              icon: CupertinoIcons.music_note_list,
                              title: '没有符合条件的歌曲',
                              message: '换一个筛选条件，或先扫描一次曲库。',
                              actionLabel: '去扫描',
                              onAction: () =>
                                  Navigator.of(context).maybePop(),
                            )
                          else if (fnBpOf(context) == FnBp.desktop)
                            FnSongTable(
                              songs: list,
                              favoriteIds: _favIds,
                              currentId:
                                  PlayerController.instance.current?.id,
                              isPlaying: PlayerController.instance.isPlaying,
                              sortColumn: switch (_sort) {
                                'artist' => 1,
                                'duration' => 3,
                                'recent' => null,
                                _ => 0,
                              },
                              sortAscending: _sort != 'duration',
                              onSort: (col) => setState(() => _sort =
                                  switch (col) {
                                    1 => 'artist',
                                    3 => 'duration',
                                    _ => 'title',
                                  }),
                              onPlay: (i) {
                                PlayerController.instance.playList(list, i);
                              },
                              onMore: (i) => showTrackMenu(
                                context,
                                list[i],
                                isFavorite: _favIds.contains(list[i].id),
                                onFavoriteChanged: () => _toggleFav(list[i]),
                              ),
                              onFavorite: (i) => _toggleFav(list[i]),
                            )
                          else
                            for (var i = 0; i < list.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: kFnPad - 8),
                                child: FnSongRow(
                                  song: list[i],
                                  ord: (i + 1).toString(),
                                  isCurrent: PlayerController
                                          .instance.current?.id ==
                                      list[i].id,
                                  isPlaying:
                                      PlayerController.instance.isPlaying,
                                  onTap: () {
                                    PlayerController.instance.playList(list, i);
                                  },
                                  onMore: () => showTrackMenu(
                                    context,
                                    list[i],
                                    isFavorite:
                                        _favIds.contains(list[i].id),
                                    onFavoriteChanged: () =>
                                        _toggleFav(list[i]),
                                  ),
                                ),
                              ),
                          FnPageFoot(
                            left:
                                '${list.length} TRACKS · ${fmtDuration(total)}',
                            right: '扫描更新',
                            onRight: () =>
                                Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

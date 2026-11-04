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
  /// 每页条数：首屏更快，滚动到底再追加下一页，避免一次返回整库。
  static const int _pageSize = 200;

  bool _loading = true;
  bool _loadingMore = false;
  bool _pagingStopped = false;
  String? _error;
  List<Song> _songs = const [];
  int _total = 0;
  int _page = 1;
  Set<int> _favIds = <int>{};
  String _sort = 'title';
  String _filter = 'all';
  final ScrollController _scroll = ScrollController();

  bool get _hasMore => _songs.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _pagingStopped = false;
      _error = null;
    });
    try {
      final res = await Future.wait<Object>([
        ApiClient.instance.fetchSongPage(page: 1, pageSize: _pageSize),
        ApiClient.instance.fetchFavorites(),
      ]);
      if (!mounted) return;
      final firstPage = res[0] as SongPage;
      setState(() {
        _songs = firstPage.items;
        _total = firstPage.total;
        _page = 1;
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

  /// 滚动接近底部时追加下一页。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _pagingStopped || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ApiClient.instance.fetchSongPage(
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      final Set<int> loadedIds = _songs.map((s) => s.id).toSet();
      setState(() {
        _songs = [
          ..._songs,
          ...next.items.where((s) => !loadedIds.contains(s.id)),
        ];
        _total = next.total;
        _page = next.page;
        _loadingMore = false;
      });
      // 追加后仍在底部（列表还没填满屏幕）时继续补，直到能滚动为止。
      if (_scroll.hasClients && _scroll.position.extentAfter < 100) {
        _loadMore();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _pagingStopped = true;
      });
      fnToast(context, '加载更多失败：$e');
    }
  }

  /// 「播放全部 / 随机」：先把剩余页补齐，保证覆盖整个曲库。
  Future<void> _playAll(bool shuffle) async {
    if (_hasMore && !_pagingStopped) {
      setState(() => _loadingMore = true);
      while (mounted && _hasMore && !_pagingStopped) {
        await _loadMore();
      }
      if (mounted) setState(() => _loadingMore = false);
    }
    if (!mounted) return;
    final list = _visible;
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
      if (!mounted) return;
      // 收藏状态本地更新即可，避免为了一个标记重新拉取整库分页。
      setState(() {
        _favIds = on ? ({..._favIds}..remove(song.id)) : {..._favIds, song.id};
      });
      fnToast(context, on ? '已取消收藏' : '已收藏');
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
    // 分页加载中时同时给出「已加载 / 总数」，避免看起来像丢了歌；
    // 搜索或本地筛选时列表是子集，不再显示总数。
    final bool narrowed = widget.query.trim().isNotEmpty || _filter != 'all';
    final String countText = (_hasMore && !narrowed)
        ? '${list.length} / 共 $_total 首'
        : '${list.length} 首';
    return Scaffold(
      backgroundColor: FnColors.base,
      body: Column(
        children: [
          if (wide)
            FnPageHead(
              eyebrow: 'SONGS',
              title: title,
              subtitle: widget.query.isEmpty
                  ? '$countText · ${fmtDuration(total)}'
                  : '匹配「${widget.query}」· $countText',
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
                    : CustomScrollView(
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                  fnPagePad(context), 14, fnPagePad(context), 12),
                              child: Row(
                                children: [
                                  FnButton(
                                    label: '播放全部',
                                    icon: Icons.play_arrow_rounded,
                                    onTap: () => _playAll(false),
                                    size: FnButtonSize.sm,
                                  ),
                                  const SizedBox(width: 8),
                                  FnButton(
                                    label: '随机',
                                    icon: Icons.shuffle_rounded,
                                    variant: FnButtonVariant.soft,
                                    onTap: () => _playAll(true),
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
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
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
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
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
                                      '$countText · ${fmtDuration(total)} · '
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
                          ),
                          if (list.isEmpty)
                            SliverToBoxAdapter(
                              child: FnEmpty(
                                icon: CupertinoIcons.music_note_list,
                                title: '没有符合条件的歌曲',
                                message: '换一个筛选条件，或先扫描一次曲库。',
                                actionLabel: '去扫描',
                                onAction: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                            )
                          else if (fnBpOf(context) == FnBp.desktop)
                            SliverToBoxAdapter(
                              child: FnSongTable(
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
                              ),
                            )
                          else
                            SliverList.builder(
                              itemCount: list.length,
                              itemBuilder: (context, i) => Padding(
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
                            ),
                          if (_loadingMore || (_hasMore && !_pagingStopped))
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.6),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '正在加载更多 · ${list.length} / $_total',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: FnColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: FnPageFoot(
                              left:
                                  '${list.length} TRACKS · ${fmtDuration(total)}',
                              right: '扫描更新',
                              onRight: () =>
                                  Navigator.of(context).maybePop(),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: fnBottomGapOf(context)),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

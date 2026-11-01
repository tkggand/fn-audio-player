import 'dart:async';

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
import '../widgets/track_menu_sheet.dart';

/// 搜索：最近搜索 / 热门搜索 / 流派入口 + 分类结果。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _historyKey = 'fn_search_history';

  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _loading = false;
  String? _error;

  List<String> _history = const [];
  List<Song> _songs = const [];
  List<Playlist> _playlists = const [];
  List<AggregateItem> _albums = const [];
  List<AggregateItem> _artists = const [];
  List<GenreInfo> _genres = const [];
  Set<int> _favIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadStatic();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadStatic() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? const <String>[];
    try {
      final res = await Future.wait<Object>([
        ApiClient.instance.fetchGenres(),
        ApiClient.instance.fetchAggregate(by: 'album', pageSize: 200),
        ApiClient.instance.fetchAggregate(by: 'artist', pageSize: 300),
        ApiClient.instance.fetchPlaylists(),
        ApiClient.instance.fetchFavorites(),
      ]);
      if (!mounted) return;
      setState(() {
        _history = history;
        _genres = res[0] as List<GenreInfo>;
        _albums = (res[1] as AggregatePage).items;
        _artists = (res[2] as AggregatePage).items;
        _playlists = res[3] as List<Playlist>;
        _favIds = (res[4] as List<Song>).map((s) => s.id).toSet();
      });
    } catch (_) {
      if (mounted) setState(() => _history = history);
    }
  }

  Future<void> _remember(String q) async {
    if (q.isEmpty) return;
    final next = [q, ..._history.where((x) => x != q)].take(8).toList();
    setState(() => _history = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

  void _onChanged(String v) {
    setState(() => _query = v.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _search);
  }

  Future<void> _search() async {
    final q = _query;
    if (q.isEmpty) {
      setState(() {
        _songs = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await ApiClient.instance.fetchSongs(q: q);
      if (!mounted || q != _query) return;
      setState(() {
        _songs = songs;
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

  void _applyQuery(String q) {
    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    _query = q;
    _remember(q);
    _search();
    _focus.unfocus();
  }

  Future<void> _clearHistory() async {
    setState(() => _history = const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) fnToast(context, '搜索记录已清空');
  }

  Future<void> _toggleFollow(String name) async {
    final followed = _artists.any((a) => a.name == name && a.followed);
    try {
      if (followed) {
        await ApiClient.instance.unfollowArtist(name);
      } else {
        await ApiClient.instance.followArtist(name);
      }
      if (mounted) fnToast(context, followed ? '已取消关注' : '已关注 $name');
    } catch (e) {
      if (mounted) fnToast(context, '操作失败：$e');
    }
  }

  bool _match(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  List<AggregateItem> get _matchedAlbums =>
      _query.isEmpty ? const [] : _albums.where((a) => _match(a.name)).toList();

  List<AggregateItem> get _matchedArtists => _query.isEmpty
      ? const []
      : _artists.where((a) => _match(a.name)).toList();

  List<Playlist> get _matchedPlaylists => _query.isEmpty
      ? const []
      : _playlists.where((p) => _match(p.name)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FnColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          FnIconBtn(
            icon: CupertinoIcons.chevron_back,
            variant: FnIconBtnVariant.plain,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: FnColors.surface2,
                borderRadius: BorderRadius.circular(12),
                // 聚焦时不额外描边：输入框不随焦点变色。
                border: Border.all(color: FnColors.line),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.search,
                      size: 17, color: FnColors.textTertiary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: (v) {
                        _search();
                        _remember(v.trim());
                        _focus.unfocus();
                      },
                      style: TextStyle(
                          fontSize: 14, color: FnColors.textPrimary),
                      cursorColor: FnColors.lime,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索歌曲、专辑、艺人',
                        hintStyle: TextStyle(
                            fontSize: 14, color: FnColors.textTertiary),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _ctrl.clear();
                        _onChanged('');
                        _focus.requestFocus();
                      },
                      child: Icon(CupertinoIcons.xmark_circle_fill,
                          size: 16, color: FnColors.textTertiary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('取消',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FnColors.limeText)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_query.isEmpty) return _emptyState();
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: FnEmpty(
          icon: CupertinoIcons.exclamationmark_circle,
          title: '搜索失败',
          message: _error,
          actionLabel: '重试',
          onAction: _search,
        ),
      );
    }
    if (_songs.isEmpty &&
        _matchedAlbums.isEmpty &&
        _matchedArtists.isEmpty &&
        _matchedPlaylists.isEmpty) {
      return Center(
        child: FnEmpty(
          icon: CupertinoIcons.search,
          title: '没有找到「$_query」',
          message: '试试歌曲名、艺人、专辑，或减少关键词。',
          actionLabel: '清空搜索词',
          onAction: () {
            _ctrl.clear();
            _onChanged('');
          },
        ),
      );
    }

    final albums = _matchedAlbums;
    final artists = _matchedArtists;
    final lists = _matchedPlaylists;
    return ListView(
      padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
      physics: const BouncingScrollPhysics(),
      children: [
        if (_songs.isNotEmpty) ...[
          _resultHead('单曲', '${_songs.length} RESULTS'),
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
                onFavoriteChanged: () => _loadStatic(),
              ),
            )
          else
            for (var i = 0; i < _songs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad - 8),
              child: FnSongRow(
                song: _songs[i],
                subtitle: '${_songs[i].artist} · ${_songs[i].album}',
                isCurrent:
                    PlayerController.instance.current?.id == _songs[i].id,
                isPlaying: PlayerController.instance.isPlaying,
                onTap: () {
                  PlayerController.instance.playList(_songs, i);
                },
                onMore: () => showTrackMenu(
                  context,
                  _songs[i],
                  isFavorite: _favIds.contains(_songs[i].id),
                  onFavoriteChanged: () => _loadStatic(),
                ),
              ),
            ),
        ],
        if (albums.isNotEmpty) ...[
          _resultHead('专辑', '${albums.length} ALBUMS'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kFnPad),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: fnGridCols(context,
                    mobile: 2, laptop: 4, desktop: 6),
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 0.74,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) {
                final a = albums[i];
                final id = a.id ?? 0;
                return FnAlbumCell(
                  albumId: id,
                  name: a.name,
                  artist: a.subtitle ?? '',
                  onTap: () => context.push(
                      '/album/$id?artist=${Uri.encodeComponent(a.subtitle ?? '')}&title=${Uri.encodeComponent(a.name)}'),
                );
              },
            ),
          ),
        ],
        if (artists.isNotEmpty) ...[
          _resultHead('艺人', '${artists.length} ARTISTS'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kFnPad),
            child: Column(
              children: [
                for (final a in artists)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context
                        .push('/artist/${Uri.encodeComponent(a.name)}'),
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
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(
                                    '${a.songCount} 首${a.subtitle == null ? '' : ' · ${a.subtitle}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: FnColors.textSecondary)),
                              ],
                            ),
                          ),
                          _followPill(a),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (lists.isNotEmpty) ...[
          _resultHead('歌单', '${lists.length} PLAYLISTS'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kFnPad),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: fnGridCols(context,
                    mobile: 2, laptop: 4, desktop: 6),
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 0.76,
              ),
              itemCount: lists.length,
              itemBuilder: (context, i) {
                final p = lists[i];
                return FnPlaylistCell(
                  title: p.name,
                  count: p.songCount,
                  coverSongId: p.coverSongId,
                  sub: p.tracks.isEmpty ? null : p.tracks.first.artist,
                  onTap: () => context.push('/playlist/${p.id}'),
                );
              },
            ),
          ),
        ],
        FnPageFoot(left: 'RESULTS FOR 「$_query」', right: 'LOCAL INDEX'),
      ],
    );
  }

  Widget _resultHead(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 20, kFnPad, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title, style: FnTextStyles.of(context).h2),
          ),
          Text(sub,
              style: TextStyle(
                fontSize: 10.5,
                fontFamily: FnText.monoFamily.first,
                color: FnColors.textTertiary,
              )),
        ],
      ),
    );
  }

  Widget _followPill(AggregateItem a) {
    final on = a.followed;
    return GestureDetector(
      onTap: () => _toggleFollow(a.name),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on ? FnColors.limeSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: on ? FnColors.lime : FnColors.line2),
        ),
        child: Row(
          children: [
            Icon(on ? Icons.check_rounded : Icons.add_rounded,
                size: 13, color: on ? FnColors.lime : FnColors.textSecondary),
            const SizedBox(width: 3),
            Text(on ? '已关注' : '关注',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: on ? FnColors.lime : FnColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final hot = <String>[
      ..._genres.take(4).map((g) => g.name),
      ..._artists.take(4).map((a) => a.name),
    ];
    return ListView(
      padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('最近搜索', style: FnTextStyles.of(context).h3),
              ),
              if (_history.isNotEmpty)
                GestureDetector(
                  onTap: _clearHistory,
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.trash,
                          size: 12, color: FnColors.textTertiary),
                      const SizedBox(width: 4),
                      Text('清空',
                          style: TextStyle(
                              fontSize: 11, color: FnColors.textTertiary)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 4),
            child: Text('还没有搜索记录',
                style:
                    TextStyle(fontSize: 10, color: FnColors.textTertiary)),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kFnPad),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in _history)
                  FnChip(
                    label: h,
                    icon: CupertinoIcons.clock,
                    selected: false,
                    small: true,
                    onTap: () => _applyQuery(h),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 22, kFnPad, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('热门搜索', style: FnTextStyles.of(context).h3),
              ),
              Text('今天',
                  style: TextStyle(fontSize: 10.5, color: FnColors.textTertiary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad - 10),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // design/v3 css/pages/search.css `.hot-grid`：mobile 单列，laptop/desktop 两列。
              crossAxisCount: fnBpOf(context) == FnBp.mobile ? 1 : 2,
              mainAxisSpacing: 2,
              crossAxisSpacing: 28,
              mainAxisExtent: 40,
            ),
            itemCount: hot.length,
            itemBuilder: (context, i) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _applyQuery(hot[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFamily: FnText.monoFamily.first,
                            color: i == 0
                                ? FnColors.lime
                                : i == 1
                                    ? FnColors.gold
                                    : i == 2
                                        ? FnColors.cyan
                                        : FnColors.textTertiary,
                          )),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(hot[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500)),
                    ),
                    if (i < 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: FnColors.coralSoft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('HOT',
                            style: TextStyle(
                                fontSize: 9,
                                fontFamily: FnText.monoFamily.first,
                                color: FnColors.coral)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 22, kFnPad, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('按流派浏览', style: FnTextStyles.of(context).h3),
              ),
              GestureDetector(
                onTap: () => context.go('/library'),
                child: Text('全部',
                    style: TextStyle(
                        fontSize: 10.5, color: FnColors.textTertiary)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              mainAxisExtent: fnGenreTileHeight(context),
            ),
            itemCount: _genres.length,
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
        FnPageFoot(left: 'SEARCH · LOCAL INDEX', right: '${_songs.length} 首索引'),
      ],
    );
  }
}

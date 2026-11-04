import 'dart:async';

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

/// 曲库：歌曲 / 专辑 / 艺人 / 流派 / 收藏 / 歌单 六个分段
/// （design/v3 DESIGN.md §4 的 6 分栏口径；原型 library.js 仅列出 5 段）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, this.initialTab = 'songs'});

  final String initialTab;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

enum _Sort { title, artist, album, duration, format }

class _LibraryPageState extends State<LibraryPage>
    with FnThemeAware<LibraryPage> {
  static const _tabs = [
    'songs',
    'albums',
    'artists',
    'genres',
    'favorites',
    'playlists'
  ];
  static const _tabLabels = ['歌曲', '专辑', '艺人', '流派', '收藏', '歌单'];

  late String _tab =
      _tabs.contains(widget.initialTab) ? widget.initialTab : 'songs';
  bool _loading = true;
  String? _error;

  List<Song> _songs = const [];
  List<Song> _favs = const [];
  List<Playlist> _playlists = const [];
  List<FollowedArtist> _followed = const [];
  List<GenreInfo> _genres = const [];
  List<AggregateItem> _albums = const [];
  List<AggregateItem> _artists = const [];

  _Sort _sort = _Sort.title;
  bool _sortAsc = true;
  String _filter = 'all';
  String _query = '';
  final _searchCtrl = TextEditingController();

  /// 播放状态监听：列表行的高亮只依赖「当前歌曲 + 是否播放」，
  /// 这里做差异判断后再 setState，避免进度每 500ms 触发的全列表重建。
  StreamSubscription<void>? _playerSub;
  int? _lastSongId;
  bool _lastPlaying = false;

  @override
  void initState() {
    super.initState();
    _load();
    final c = PlayerController.instance;
    _lastSongId = c.current?.id;
    _lastPlaying = c.isPlaying;
    _playerSub = c.stateChanges.stream.listen((_) {
      if (!mounted) return;
      final playing = c.isPlaying;
      final id = c.current?.id;
      if (id == _lastSongId && playing == _lastPlaying) return;
      setState(() {
        _lastSongId = id;
        _lastPlaying = playing;
      });
    });
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 侧栏「专辑 / 艺人 / 流派」以 /library?tab=... 复用同一分支，需随 query 切换分栏。
    final next = widget.initialTab;
    if (next != oldWidget.initialTab && _tabs.contains(next) && next != _tab) {
      setState(() => _tab = next);
    }
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
        ApiClient.instance.fetchFollowedArtists(),
        ApiClient.instance.fetchGenres(),
        ApiClient.instance.fetchAggregate(by: 'album', pageSize: 200),
        ApiClient.instance.fetchAggregate(by: 'artist', pageSize: 300),
        ApiClient.instance.fetchPlaylists(),
      ]);
      if (!mounted) return;
      setState(() {
        _songs = res[0] as List<Song>;
        _favs = res[1] as List<Song>;
        _followed = res[2] as List<FollowedArtist>;
        _genres = res[3] as List<GenreInfo>;
        _albums = (res[4] as AggregatePage).items;
        _artists = (res[5] as AggregatePage).items;
        _playlists = res[6] as List<Playlist>;
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

  Set<int> get _favIds => _favs.map((s) => s.id).toSet();
  Set<String> get _followNames => _followed.map((a) => a.name).toSet();

  /// design/v3 js/pages/library.js `matchSong` 同口径：标题 / 艺人 / 专辑 / 流派。
  bool _matchText(String text) {
    if (_query.isEmpty) return true;
    return text.toLowerCase().contains(_query.toLowerCase());
  }

  bool _matchSong(Song s) =>
      _matchText('${s.title} ${s.artist} ${s.album} ${s.genre ?? ''}');

  List<AggregateItem> get _visibleAlbums => _albums
      .where((a) => _matchText('${a.name} ${a.subtitle ?? ''}'))
      .toList();

  List<AggregateItem> get _visibleArtists => _artists
      .where((a) => _matchText('${a.name} ${a.subtitle ?? ''}'))
      .toList();

  List<GenreInfo> get _visibleGenres =>
      _genres.where((g) => _matchText(g.name)).toList();

  void _moreSheet() {
    final controller = TextEditingController(text: _query);
    showFnSheet<void>(
      context,
      eyebrow: 'LIBRARY',
      title: '曲库选项',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: controller,
            autofocus: false,
            onChanged: (v) {
              _searchCtrl.text = v;
              setState(() => _query = v.trim());
            },
            decoration: InputDecoration(
              hintText: '过滤当前列表',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: FnColors.glassLight,
              // 与登录 / 搜索页表单一致：圆角小一档，不再用胶囊形。
              border: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: FnColors.line),
              ),
            ),
          ),
        ),
        FnOptionRow(
          title: '扫描曲库',
          subtitle: '重新扫描本地目录',
          icon: Icons.qr_code_scanner_rounded,
          onTap: () {
            Navigator.pop(context);
            context.push('/scan');
          },
        ),
        FnOptionRow(
          title: '搜索',
          subtitle: '搜索歌曲、专辑、艺人',
          icon: CupertinoIcons.search,
          onTap: () {
            Navigator.pop(context);
            context.push('/search');
          },
        ),
      ],
    ).whenComplete(controller.dispose);
  }

  List<Song> _sorted(List<Song> src) {
    final list = [...src];
    int cmp(Song a, Song b) => switch (_sort) {
          _Sort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          _Sort.artist =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          _Sort.album => a.album.toLowerCase().compareTo(b.album.toLowerCase()),
          _Sort.duration => (a.duration ?? 0).compareTo(b.duration ?? 0),
          _Sort.format => fnFormatOf(a).label.compareTo(fnFormatOf(b).label),
        };
    list.sort((a, b) {
      final r = cmp(a, b);
      if (r == 0) return a.id.compareTo(b.id);
      return _sortAsc ? r : -r;
    });
    return list;
  }

  /// 桌面表头排序列：0 标题 / 1 艺人 / 2 专辑 / 3 时长（design/v3 library.js SORT_LABELS）。
  int? get _sortColumn => switch (_sort) {
        _Sort.title => 0,
        _Sort.artist => 1,
        _Sort.album => 2,
        _Sort.duration => 3,
        _Sort.format => null,
      };

  void _applySort(int column) {
    final next = switch (column) {
      0 => _Sort.title,
      1 => _Sort.artist,
      2 => _Sort.album,
      3 => _Sort.duration,
      _ => _sort,
    };
    setState(() {
      if (_sort == next) {
        _sortAsc = !_sortAsc;
      } else {
        _sort = next;
        _sortAsc = next != _Sort.duration;
      }
    });
  }

  List<Song> get _visibleSongs {
    var list = _tab == 'favorites' ? _favs : _songs;
    list = list.where(_matchSong).toList();
    if (_filter == 'lossless') {
      list = list.where((s) => !s.isLossy).toList();
    } else if (_filter == 'favorites') {
      final ids = _favIds;
      list = list.where((s) => ids.contains(s.id)).toList();
    }
    return _sorted(list);
  }

  void _playAll(List<Song> list) {
    if (list.isEmpty) return;
    PlayerController.instance.playList(list, 0);
    fnToast(context, '开始播放 · ${list.length} 首', icon: Icons.play_arrow_rounded);
  }

  void _shuffleAll(List<Song> list) {
    if (list.isEmpty) return;
    final pool = [...list]..shuffle();
    if (!PlayerController.instance.shuffle)
      PlayerController.instance.toggleShuffle();
    PlayerController.instance.playList(pool, 0);
    fnToast(context, '随机播放已开启', icon: Icons.shuffle_rounded);
  }

  Future<void> _createPlaylist() async {
    final name = await _askName();
    if (name == null || name.trim().isEmpty) return;
    try {
      final p = await ApiClient.instance.createPlaylist(name.trim());
      await _load();
      if (!mounted) return;
      fnToast(context, '已创建「${p.name}」');
    } catch (e) {
      if (mounted) fnToast(context, '创建失败：$e');
    }
  }

  Future<String?> _askName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('新建歌单', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FnColors.textPrimary),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
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

  void _sortSheet() {
    const labels = {
      _Sort.title: '标题',
      _Sort.artist: '艺人',
      _Sort.album: '专辑',
      _Sort.duration: '时长',
      _Sort.format: '格式',
    };
    showFnSheet<void>(
      context,
      eyebrow: 'SORT',
      title: '排序方式',
      children: [
        for (final e in labels.entries)
          FnOptionRow(
            title: e.value,
            icon: Icons.sort_rounded,
            on: _sort == e.key,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                if (_sort == e.key) {
                  _sortAsc = !_sortAsc;
                } else {
                  _sort = e.key;
                  _sortAsc = e.key != _Sort.duration;
                }
              });
            },
          ),
      ],
    );
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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
            title: '曲库加载失败',
            message: _error,
            actionLabel: '重试',
            onAction: _load,
          ),
        ),
      );
    }
    final bp = fnBpOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: FnPageHead(
              eyebrow: 'LIBRARY',
              title: '曲库',
              subtitle:
                  '${_songs.length} 首歌 · ${_artists.length} 位艺人 · ${_albums.length} 张专辑',
              actions: [
                if (!bp.isMobile)
                  _LibSearchField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() => _query = v.trim());
                      }),
                if (bp.isMobile) ...[
                  FnIconBtn(
                    icon: Icons.more_vert_rounded,
                    onTap: _moreSheet,
                  ),
                ] else ...[
                  FnIconBtn(
                    icon: Icons.qr_code_scanner_rounded,
                    onTap: () => context.push('/scan'),
                  ),
                  FnIconBtn(
                    icon: CupertinoIcons.search,
                    onTap: () => context.push('/search'),
                  ),
                ],
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _LibTabsDelegate(
              labels: _tabLabels,
              index: _tabs.indexOf(_tab),
              onChanged: (i) => setState(() => _tab = _tabs[i]),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 14),
                ..._panel(),
                FnPageFoot(
                  left:
                      '${_songs.length} 首 · ${_favs.length} 收藏 · ${_playlists.length} 歌单',
                  right: '扫描设置',
                  onRight: () => context.push('/scan'),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _panel() {
    switch (_tab) {
      case 'albums':
        return _albumPanel();
      case 'artists':
        return _artistPanel();
      case 'genres':
        return _genrePanel();
      case 'favorites':
        return _favPanel();
      case 'playlists':
        return _playlistPanel();
      default:
        return _songPanel();
    }
  }

  List<Widget> _songPanel() {
    final list = _visibleSongs;
    return [
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: FnEmpty(
            icon: CupertinoIcons.music_note_2,
            title: '没有匹配的歌曲',
            message: _query.isEmpty ? '曲库还是空的，先扫描一次吧。' : '换一个关键词试试。',
          ),
        )
      else ...[
        _toolbar(list),
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 10),
          child: Row(
            children: [
              Icon(Icons.dns_rounded, size: 12, color: FnColors.textTertiary),
              const SizedBox(width: 5),
              Text(
                '本地曲库 · 共 ${_songs.length} 首 · ${fmtDuration(list.fold<double>(0, (a, s) => a + (s.duration ?? 0)))}',
                style: TextStyle(fontSize: 10.5, color: FnColors.textTertiary),
              ),
            ],
          ),
        ),
        if (fnBpOf(context) == FnBp.desktop)
          FnSongTable(
            songs: list,
            favoriteIds: _favIds,
            currentId: PlayerController.instance.current?.id,
            isPlaying: PlayerController.instance.isPlaying,
            sortColumn: _sortColumn,
            sortAscending: _sortAsc,
            onSort: _applySort,
            onPlay: (i) {
              PlayerController.instance.playList(list, i);
            },
            onMore: (i) => showTrackMenu(context, list[i],
                isFavorite: _favIds.contains(list[i].id),
                onFavoriteChanged: () => _toggleFav(list[i])),
            onFavorite: (i) => _toggleFav(list[i]),
          )
        else
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad - 8),
              child: FnSongRow(
                song: list[i],
                ord: (i + 1).toString(),
                isCurrent: PlayerController.instance.current?.id == list[i].id,
                isPlaying: PlayerController.instance.isPlaying,
                onTap: () {
                  PlayerController.instance.playList(list, i);
                },
                onMore: () => showTrackMenu(context, list[i],
                    isFavorite: _favIds.contains(list[i].id),
                    onFavoriteChanged: () => _toggleFav(list[i])),
              ),
            ),
      ],
    ];
  }

  Widget _toolbar(List<Song> list) {
    const sorts = {
      'title': '标题',
      'artist': '艺人',
      'album': '专辑',
      'duration': '时长',
      'format': '格式',
    };
    final bp = fnBpOf(context);
    // 工具栏内统一用 FnButton(sm)，保证播放、排序、筛选三种按钮高度与内边距一致。
    FnButton filter(String label, String value) => FnButton(
          label: label,
          size: FnButtonSize.sm,
          variant:
              _filter == value ? FnButtonVariant.primary : FnButtonVariant.soft,
          onTap: () => setState(() => _filter = value),
        );
    final filters = [
      filter('全部', 'all'),
      filter('无损以上', 'lossless'),
      filter('已收藏', 'favorites'),
    ];
    final sortPill = bp == FnBp.desktop
        ? null
        : FnButton(
            label: sorts[_sort.name]!,
            icon: Icons.sort_rounded,
            variant: FnButtonVariant.soft,
            size: FnButtonSize.sm,
            onTap: _sortSheet,
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 10),
          child: Row(
            children: [
              FnButton(
                label: '播放全部',
                icon: Icons.play_arrow_rounded,
                onTap: () => _playAll(list),
                size: FnButtonSize.sm,
              ),
              const SizedBox(width: 8),
              FnButton(
                label: '随机',
                icon: Icons.shuffle_rounded,
                variant: FnButtonVariant.soft,
                onTap: () => _shuffleAll(list),
                size: FnButtonSize.sm,
              ),
              const Spacer(),
              // 筛选标记与「播放全部」同一水平线、靠最右；窄屏放不下时仍单独成行。
              if (sortPill != null) ...[sortPill, const SizedBox(width: 8)],
              if (bp != FnBp.mobile)
                for (final c in filters) ...[c, const SizedBox(width: 8)],
            ],
          ),
        ),
        if (bp == FnBp.mobile)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: kFnPad),
              children: [
                for (final c in filters) ...[c, const SizedBox(width: 8)],
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  List<Widget> _albumPanel() {
    final albums = _visibleAlbums;
    return [
      if (albums.isEmpty)
        FnEmpty(
          icon: CupertinoIcons.square_stack,
          title: _albums.isEmpty ? '还没有专辑' : '没有匹配的专辑',
          message: _albums.isEmpty ? '完成一次曲库扫描后，专辑会自动归类。' : '换一个关键词试试。',
          compact: true,
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  fnGridCols(context, mobile: 2, laptop: 3, desktop: 6),
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
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
    ];
  }

  List<Widget> _artistPanel() {
    final follows = _followNames;
    final artists = _visibleArtists;
    return [
      if (artists.isEmpty)
        FnEmpty(
          icon: CupertinoIcons.person_2,
          title: _artists.isEmpty ? '还没有艺人信息' : '没有匹配的艺人',
          message: _artists.isEmpty ? '扫描完成后，这里会按艺人聚合你的曲库。' : '换一个关键词试试。',
          compact: true,
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
          child: Column(
            children: [
              for (final a in artists)
                _ArtistRow(
                  name: a.name,
                  count: a.songCount,
                  sub: a.subtitle,
                  followed: follows.contains(a.name),
                  onTap: () =>
                      context.push('/artist/${Uri.encodeComponent(a.name)}'),
                  onFollow: () => _toggleFollow(a.name),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _genrePanel() {
    final genres = _visibleGenres;
    return [
      if (genres.isEmpty)
        FnEmpty(
          icon: CupertinoIcons.waveform,
          title: _genres.isEmpty ? '还没有流派标签' : '没有匹配的流派',
          message: _genres.isEmpty ? '歌曲带有的风格标签会聚合成这里的分类。' : '换一个关键词试试。',
          compact: true,
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  fnGridCols(context, mobile: 2, laptop: 3, desktop: 6),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              mainAxisExtent: fnGenreTileHeight(context),
            ),
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final g = genres[i];
              return FnGenreTile(
                name: g.name,
                count: g.songCount,
                onTap: () =>
                    context.push('/genre/${Uri.encodeComponent(g.name)}'),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _favPanel() {
    final list = _visibleSongs;
    if (_favs.isEmpty) {
      return [
        const FnEmpty(
          icon: CupertinoIcons.heart,
          title: '还没有收藏',
          message: '在歌曲行或歌曲菜单点按心形，就能在这里找到它们。',
        ),
      ];
    }
    return [
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: FnEmpty(
            icon: CupertinoIcons.music_note_2,
            title: '没有匹配的收藏',
            message: '换一个关键词试试。',
            compact: true,
          ),
        )
      else ...[
        _toolbar(list),
        if (fnBpOf(context) == FnBp.desktop)
          FnSongTable(
            songs: list,
            favoriteIds: _favIds,
            currentId: PlayerController.instance.current?.id,
            isPlaying: PlayerController.instance.isPlaying,
            sortColumn: _sortColumn,
            sortAscending: _sortAsc,
            onSort: _applySort,
            onPlay: (i) {
              PlayerController.instance.playList(list, i);
            },
            onMore: (i) => showTrackMenu(context, list[i],
                isFavorite: true, onFavoriteChanged: () => _toggleFav(list[i])),
            onFavorite: (i) => _toggleFav(list[i]),
          )
        else
          for (var i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kFnPad - 8),
              child: FnSongRow(
                song: list[i],
                ord: (i + 1).toString(),
                isCurrent: PlayerController.instance.current?.id == list[i].id,
                isPlaying: PlayerController.instance.isPlaying,
                onTap: () {
                  PlayerController.instance.playList(list, i);
                },
                onMore: () => showTrackMenu(context, list[i],
                    isFavorite: true,
                    onFavoriteChanged: () => _toggleFav(list[i])),
              ),
            ),
      ],
    ];
  }

  List<Widget> _playlistPanel() {
    return [
      if (_playlists.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: FnEmpty(
            icon: CupertinoIcons.music_note_list,
            title: '还没有歌单',
            message: '新建一个歌单来整理你的收藏。',
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(kFnPad, 2, kFnPad, 12),
          child: GestureDetector(
            onTap: _createPlaylist,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: FnColors.surface,
                borderRadius: BorderRadius.circular(FnRadius.sm),
                border: Border.all(color: FnColors.line),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: FnColors.limeSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 18, color: FnColors.limeText),
                  ),
                  const SizedBox(width: 12),
                  const Text('新建歌单',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kFnPad),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:
                  fnGridCols(context, mobile: 2, laptop: 3, desktop: 5),
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              childAspectRatio: 0.76,
            ),
            itemCount: _playlists.length,
            itemBuilder: (context, i) {
              final p = _playlists[i];
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
    ];
  }
}

/// 页头过滤框（design/v3 css/pages/library.css `.lib-filter`：240 × 38）。
class _LibSearchField extends StatefulWidget {
  const _LibSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_LibSearchField> createState() => _LibSearchFieldState();
}

class _LibSearchFieldState extends State<_LibSearchField> {
  /// 与登录 / 搜索页表单一致：圆角小一档，图标与操作都嵌在框内。
  static const _radius = BorderRadius.all(Radius.circular(10));

  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_syncText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncText);
    super.dispose();
  }

  void _syncText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 38,
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: 13, color: FnColors.textPrimary),
        cursorColor: FnColors.lime,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: FnColors.surface2,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          prefixIcon: Icon(CupertinoIcons.search,
              size: 16, color: FnColors.textTertiary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: _hasText
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clear,
                  child: Tooltip(
                    message: '清空',
                    child: Icon(CupertinoIcons.xmark_circle_fill,
                        size: 15, color: FnColors.textTertiary),
                  ),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 36),
          hintText: '过滤当前列表',
          hintStyle: TextStyle(fontSize: 13, color: FnColors.textTertiary),
          border: const OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide(color: FnColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: _radius,
            borderSide: BorderSide(color: FnColors.lime, width: 1.2),
          ),
        ),
      ),
    );
  }
}

/// 下划线式分栏（design/v3 DESIGN.md 六段：songs/albums/artists/genres/favorites/playlists，
/// 42px 高，激活 lime 下划）。
class _LibTabsDelegate extends SliverPersistentHeaderDelegate {
  const _LibTabsDelegate({
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  static const _h = 43.0;

  @override
  double get minExtent => _h;

  @override
  double get maxExtent => _h;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: _h,
      decoration: BoxDecoration(
        color: FnColors.base,
        border: Border(bottom: BorderSide(color: FnColors.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: fnPagePad(context)),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              _LibTab(
                label: labels[i],
                active: i == index,
                onTap: () => onChanged(i),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LibTabsDelegate old) =>
      old.index != index || old.labels != labels;
}

class _LibTab extends StatelessWidget {
  const _LibTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? FnColors.limeText : FnColors.textSecondary,
                ),
              ),
            ),
            if (active)
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: FnColors.lime,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.name,
    required this.count,
    required this.followed,
    required this.onTap,
    required this.onFollow,
    this.sub,
  });

  final String name;
  final int count;
  final bool followed;
  final VoidCallback onTap;
  final VoidCallback onFollow;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            FnArtistAvatar(name: name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    '$count 首${sub == null || sub!.isEmpty ? '' : ' · $sub'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: FnColors.textSecondary),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onFollow,
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
                    Icon(
                      followed ? Icons.check_rounded : Icons.add_rounded,
                      size: 13,
                      color: followed ? FnColors.lime : FnColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      followed ? '已关注' : '关注',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color:
                            followed ? FnColors.lime : FnColors.textSecondary,
                      ),
                    ),
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

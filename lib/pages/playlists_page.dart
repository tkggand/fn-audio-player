import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 我的歌单：概览 + 筛选 + 双列网格。
class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  bool _loading = true;
  String? _error;
  List<Playlist> _playlists = const [];
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
      final list = await ApiClient.instance.fetchPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = list;
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

  List<Playlist> get _visible {
    switch (_filter) {
      case 'empty':
        return _playlists.where((p) => p.songCount == 0).toList();
      case 'mine':
        return _playlists;
      default:
        return _playlists;
    }
  }

  int get _totalSongs =>
      _playlists.fold(0, (sum, p) => sum + p.songCount);

  Future<void> _create() async {
    final name = await _askName();
    if (name == null || name.trim().isEmpty) return;
    try {
      final p = await ApiClient.instance.createPlaylist(name.trim());
      await _load();
      if (!mounted) return;
      fnToast(context, '已创建「${p.name}」');
      context.push('/playlist/${p.id}');
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
          decoration: const InputDecoration(hintText: '给歌单起个名字'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(Playlist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('删除歌单？', style: TextStyle(fontSize: 17)),
        content: Text('「${p.name}」会被移除，歌曲本身不会删除。',
            style: TextStyle(fontSize: 13, color: FnColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.deletePlaylist(p.id);
      await _load();
      if (mounted) fnToast(context, '已删除「${p.name}」');
    } catch (e) {
      if (mounted) fnToast(context, '删除失败：$e');
    }
  }

  /// design/v3 playlists.js openMoreSheet：mobile/laptop 的筛选入口
  /// （desktop 直接显示 chips，不出「更多」）。
  void _moreSheet() {
    final mobile = fnBpOf(context) == FnBp.mobile;
    showFnSheet<void>(
      context,
      eyebrow: 'PLAYLISTS',
      title: '歌单选项',
      children: [
        if (mobile) ...[
          FnOptionRow(
            title: '新建歌单',
            subtitle: '创建一个空歌单',
            icon: Icons.add_circle_outline_rounded,
            onTap: () {
              Navigator.pop(context);
              _create();
            },
          ),
        ],
        FnOptionRow(
          title: '显示：全部',
          subtitle: '${_playlists.length} 个歌单',
          icon: Icons.queue_music_rounded,
          onTap: () {
            Navigator.pop(context);
            setState(() => _filter = 'all');
          },
        ),
        FnOptionRow(
          title: '显示：我创建',
          icon: Icons.person_outline_rounded,
          onTap: () {
            Navigator.pop(context);
            setState(() => _filter = 'mine');
          },
        ),
        FnOptionRow(
          title: '显示：空歌单',
          icon: Icons.music_note_outlined,
          onTap: () {
            Navigator.pop(context);
            setState(() => _filter = 'empty');
          },
        ),
      ],
    );
  }

  /// 卡片菜单（v3 playlistSheet）：播放 / 删除。
  /// 后端无重命名与封面更换接口，故不给出对应假入口。
  void _cardMenu(Playlist p) {
    showFnSheet<void>(
      context,
      eyebrow: 'PLAYLIST',
      title: p.name,
      subtitle: '${p.songCount} 首',
      children: [
        FnOptionRow(
          title: '播放歌单',
          icon: Icons.play_arrow_rounded,
          onTap: () {
            Navigator.pop(context);
            context.push('/playlist/${p.id}');
          },
        ),
        FnOptionRow(
          title: '删除歌单',
          icon: Icons.delete_outline_rounded,
          danger: true,
          onTap: () {
            Navigator.pop(context);
            _delete(p);
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
                      title: '歌单加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 28),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (fnBpOf(context).isWide)
                        FnPageHead(
                          eyebrow: 'PLAYLISTS',
                          title: '歌单',
                          subtitle:
                              '${_playlists.length} 个歌单 · $_totalSongs 首曲目',
                          actions: [
                            FnButton(
                              label: '新建歌单',
                              icon: Icons.add_rounded,
                              onTap: _create,
                              size: FnButtonSize.sm,
                            ),
                            // desktop 走 chips + 卡片右键菜单，页头不出「更多」。
                            if (fnBpOf(context) == FnBp.laptop)
                              FnIconBtn(
                                icon: Icons.more_vert,
                                onTap: _moreSheet,
                              ),
                          ],
                        )
                      else
                        FnNav(
                          title: '歌单',
                          subtitle: 'PLAYLISTS',
                          trailing: [
                            FnIconBtn(
                              icon: Icons.more_vert,
                              variant: FnIconBtnVariant.plain,
                              onTap: _moreSheet,
                            ),
                          ],
                        ),
                      // design/v3 playlists.css：筛选 chips 仅 desktop 显示，
                      // mobile/laptop 收进页头「更多」sheet。
                      if (fnBpOf(context) == FnBp.desktop) _filters(),
                      if (_visible.isEmpty)
                        FnEmpty(
                          icon: CupertinoIcons.music_note_list,
                          title: '这里没有歌单',
                          message: '换一个筛选条件，或新建一个歌单。',
                          actionLabel: '新建歌单',
                          onAction: _create,
                        )
                      else
                        _grid(),
                      FnPageFoot(
                        left: 'SORTED BY UPDATED',
                        right: '播放历史',
                        onRight: () => context.push('/history'),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// design/v3 components.css .grid-cards：mobile 2 列 / laptop 3 列 /
  /// desktop auto-fill minmax(180px, 1fr)；首格为虚线新建卡 .create-tile。
  Widget _grid() {
    final bp = fnBpOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 8, kFnPad, 0),
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
          final cell =
              (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: 16,
            children: [
              SizedBox(
                width: cell,
                child: GestureDetector(
                  onTap: _create,
                  behavior: HitTestBehavior.opaque,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(FnRadius.sm),
                        border: Border.all(color: FnColors.line2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              size: 24, color: FnColors.limeText),
                          const SizedBox(height: 7),
                          Text('新建歌单',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: FnColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              for (final p in _visible)
                SizedBox(
                  width: cell,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FnPlaylistCell(
                        title: p.name,
                        count: p.songCount,
                        coverSongId: p.coverSongId,
                        sub: p.tracks.isEmpty ? null : p.tracks.first.artist,
                        onTap: () => context.push('/playlist/${p.id}'),
                      ),
                      if (bp != FnBp.desktop)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: GestureDetector(
                            onTap: () => _cardMenu(p),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.38),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.more_vert,
                                  size: 15, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 10, kFnPad, 0),
      child: Wrap(
        spacing: 7,
        children: [
          FnChip(
            label: '全部',
            selected: _filter == 'all',
            small: true,
            onTap: () => setState(() => _filter = 'all'),
          ),
          FnChip(
            label: '我创建的',
            selected: _filter == 'mine',
            small: true,
            onTap: () => setState(() => _filter = 'mine'),
          ),
          FnChip(
            label: '空歌单',
            selected: _filter == 'empty',
            small: true,
            onTap: () => setState(() => _filter = 'empty'),
          ),
        ],
      ),
    );
  }
}

/// 歌单详情。
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  bool _loading = true;
  String? _error;
  Playlist? _playlist;

  /// desktop 批量编辑：勾选后一次性移出。
  bool _editing = false;
  final Set<int> _selected = {};

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
      final p = await ApiClient.instance
          .fetchPlaylistDetail(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _playlist = p;
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

  List<Song> get _tracks => _playlist?.tracks ?? const [];

  double get _totalSeconds =>
      _tracks.fold(0.0, (sum, s) => sum + (s.duration ?? 0));

  void _play(bool shuffle) {
    if (_tracks.isEmpty) return;
    final list = [..._tracks];
    if (shuffle) list.shuffle();
    PlayerController.instance.playList(list, 0);
    fnToast(context, shuffle ? '随机播放歌单' : '开始播放歌单',
        icon: shuffle ? Icons.shuffle_rounded : Icons.play_arrow_rounded);
  }

  Future<void> _move(int index, int delta) async {
    final p = _playlist;
    if (p == null) return;
    final target = index + delta;
    if (target < 0 || target >= p.tracks.length) return;
    final ids = p.tracks.map((s) => s.id).toList();
    final tmp = ids[index];
    ids[index] = ids[target];
    ids[target] = tmp;
    try {
      await ApiClient.instance.reorderPlaylist(p.id, ids);
      await _load();
    } catch (e) {
      if (mounted) fnToast(context, '排序失败：$e');
    }
  }

  Future<void> _setCover(Song song) async {
    final p = _playlist;
    if (p == null) return;
    try {
      await ApiClient.instance.setPlaylistCover(p.id, song.id);
      await _load();
      if (mounted) fnToast(context, '已设为歌单封面');
    } catch (e) {
      if (mounted) fnToast(context, '设置失败：$e');
    }
  }

  Future<void> _remove(Song song) async {
    final p = _playlist;
    if (p == null) return;
    try {
      await ApiClient.instance.removePlaylistTrack(p.id, song.id);
      await _load();
      if (mounted) fnToast(context, '已移出歌单');
    } catch (e) {
      if (mounted) fnToast(context, '移除失败：$e');
    }
  }

  void _toggleSelect(int index) {
    if (index < 0 || index >= _tracks.length) return;
    final id = _tracks[index].id;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selected.length == _tracks.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_tracks.map((s) => s.id));
      }
    });
  }

  Future<void> _removeSelected() async {
    final p = _playlist;
    if (p == null || _selected.isEmpty) return;
    final ids = _selected.toList();
    try {
      for (final id in ids) {
        await ApiClient.instance.removePlaylistTrack(p.id, id);
      }
      setState(() {
        _selected.clear();
        _editing = false;
      });
      await _load();
      if (mounted) fnToast(context, '已移出 ${ids.length} 首');
    } catch (e) {
      if (mounted) fnToast(context, '移除失败：$e');
    }
  }

  void _trackMenu(int index) {
    final song = _tracks[index];
    showFnSheet<void>(
      context,
      eyebrow: 'TRACK',
      title: song.title,
      subtitle: '${song.artist} · ${song.album}',
      children: [
        FnOptionRow(
          title: '设为歌单封面',
          icon: Icons.image_rounded,
          onTap: () {
            Navigator.pop(context);
            _setCover(song);
          },
        ),
        FnOptionRow(
          title: '上移',
          icon: Icons.arrow_upward_rounded,
          onTap: index == 0
              ? null
              : () {
                  Navigator.pop(context);
                  _move(index, -1);
                },
        ),
        FnOptionRow(
          title: '下移',
          icon: Icons.arrow_downward_rounded,
          onTap: index == _tracks.length - 1
              ? null
              : () {
                  Navigator.pop(context);
                  _move(index, 1);
                },
        ),
        FnOptionRow(
          title: '移出歌单',
          icon: Icons.remove_circle_outline_rounded,
          danger: true,
          onTap: () {
            Navigator.pop(context);
            _remove(song);
          },
        ),
      ],
    );
  }

  Future<void> _addSongs() async {
    final p = _playlist;
    if (p == null) return;
    List<Song> candidates;
    try {
      final res = await Future.wait<Object>([
        ApiClient.instance.fetchSongs(),
        ApiClient.instance.fetchFavorites(),
      ]);
      final all = res[0] as List<Song>;
      final favs = res[1] as List<Song>;
      final existing = p.tracks.map((s) => s.id).toSet();
      final map = <int, Song>{};
      for (final s in [...favs, ...all]) {
        if (!existing.contains(s.id)) map.putIfAbsent(s.id, () => s);
      }
      candidates = map.values.toList();
    } catch (e) {
      if (mounted) fnToast(context, '加载歌曲失败：$e');
      return;
    }
    if (!mounted) return;
    await showFnSheet<void>(
      context,
      eyebrow: 'ADD TO PLAYLIST',
      title: '添加歌曲',
      subtitle: p.name,
      children: [
        for (final s in candidates)
          FnOptionRow(
            title: s.title,
            subtitle: '${s.artist} · ${s.album}',
            icon: Icons.music_note_rounded,
            onTap: () async {
              Navigator.pop(context);
              try {
                await ApiClient.instance.addPlaylistTrack(p.id, s.id);
                await _load();
                if (mounted) fnToast(context, '已添加「${s.title}」');
              } catch (e) {
                if (mounted) fnToast(context, '添加失败：$e');
              }
            },
          ),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('曲库里没有可添加的歌曲',
                style:
                    TextStyle(fontSize: 12, color: FnColors.textTertiary)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _playlist;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null || p == null
                ? Center(
                    child: FnEmpty(
                      icon: CupertinoIcons.exclamationmark_circle,
                      title: '歌单加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (fnBpOf(context).isWide)
                        FnPageHead(
                          eyebrow: 'PLAYLIST · ${_tracks.length} TRACKS',
                          title: p.name,
                          subtitle: '${p.songCount} 首 · 本地歌单',
                          actions: [
                            FnIconBtn(
                              icon: Icons.edit_rounded,
                              onTap: _addSongs,
                            ),
                            FnIconBtn(
                              icon: Icons.play_arrow_rounded,
                              onTap: _tracks.isEmpty
                                  ? null
                                  : () => PlayerController.instance
                                      .playList(_tracks, 0),
                            ),
                          ],
                        )
                      else
                        FnNav(
                          title: '歌单',
                          subtitle: 'PLAYLIST',
                          trailing: [
                            FnIconBtn(
                              icon: Icons.edit_rounded,
                              variant: FnIconBtnVariant.plain,
                              onTap: _addSongs,
                            ),
                            FnIconBtn(
                              icon: Icons.more_horiz,
                              variant: FnIconBtnVariant.plain,
                              onTap: () => fnToast(context, '更多操作开发中'),
                            ),
                          ],
                        ),
                      _hero(p),
                      _toolbar(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(kFnPad, 2, kFnPad, 8),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 12, color: FnColors.textTertiary),
                            const SizedBox(width: 5),
                            Text('仅自己可见 · 本地歌单，不参与云同步',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: FnColors.textTertiary)),
                          ],
                        ),
                      ),
                      if (_tracks.isEmpty)
                        FnEmpty(
                          icon: CupertinoIcons.music_note_list,
                          title: '歌单还是空的',
                          message: '从曲库挑几首歌，或者直接收藏正在播放的歌。',
                          actionLabel: '添加歌曲',
                          onAction: _addSongs,
                        )
                      else if (fnBpOf(context) == FnBp.desktop) ...[
                        if (_editing) _editBar(),
                        FnSongTable(
                          songs: _tracks,
                          onPlay: (i) {
                            if (_editing) {
                              _toggleSelect(i);
                              return;
                            }
                            PlayerController.instance.playList(_tracks, i);
                          },
                          onMore: _editing ? null : _trackMenu,
                          selectionMode: _editing,
                          selectedIds: _selected,
                          onToggleSelect: _toggleSelect,
                          onToggleAll: _toggleAll,
                        ),
                      ]
                      else
                        for (var i = 0; i < _tracks.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: kFnPad - 8),
                            child: FnSongRow(
                              song: _tracks[i],
                              ord: (i + 1).toString(),
                              subtitle:
                                  '${_tracks[i].artist} · ${_tracks[i].album}',
                              isCurrent: PlayerController.instance.current?.id ==
                                  _tracks[i].id,
                              isPlaying: PlayerController.instance.isPlaying,
                              onTap: () {
                                PlayerController.instance
                                    .playList(_tracks, i);
                              },
                              onMore: () => _trackMenu(i),
                            ),
                          ),
                      GestureDetector(
                        onTap: _addSongs,
                        child: Container(
                          height: 44,
                          margin:
                              const EdgeInsets.fromLTRB(kFnPad, 8, kFnPad, 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: FnColors.line2),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 15, color: FnColors.limeText),
                              const SizedBox(width: 5),
                              Text('添加歌曲到歌单',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: FnColors.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                      FnPageFoot(
                        left: 'PLAYLIST · LOCAL',
                        right: '全部歌单',
                        onRight: () => context.push('/playlists'),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _hero(Playlist p) {
    final coverId = p.coverSongId ?? (p.tracks.isNotEmpty ? p.tracks.first.id : null);
    final minutes = (_totalSeconds / 60).round();
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    // design/v3 css/pages/playlist.css：封面 200（desktop）/ 176（laptop），
    // mobile 62% 宽、最大 230 且纵向居中堆叠。
    final coverSize = mobile
        ? (MediaQuery.sizeOf(context).width * 0.62).clamp(0.0, 230.0)
        : (bp == FnBp.laptop ? 176.0 : 200.0);
    final cover = coverId == null
        ? Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: fnCoverGradient(p.name.hashCode),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.queue_music_rounded,
                size: coverSize * 0.36, color: Colors.white54),
          )
        : FnCover(songId: coverId, size: coverSize, radius: 16);
    return Padding(
      padding: EdgeInsets.fromLTRB(kFnPad, mobile ? 20 : 10, kFnPad, mobile ? 22 : 30),
      child: mobile
          ? Column(
              children: [
                cover,
                const SizedBox(height: 20),
                _playlistInfo(p, minutes, center: true),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                cover,
                const SizedBox(width: 26),
                Expanded(child: _playlistInfo(p, minutes, center: false)),
              ],
            ),
    );
  }

  Widget _playlistInfo(Playlist p, int minutes, {required bool center}) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text('PLAYLIST · LOCAL',
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 1.2,
              fontFamily: FnText.monoFamily.first,
              color: FnColors.limeText,
            )),
        const SizedBox(height: 4),
        Text(p.name,
            maxLines: 1,
            textAlign: center ? TextAlign.center : TextAlign.start,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: center ? 26 : 32,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.9)),
        const SizedBox(height: 5),
        Text(p.tracks.isEmpty ? '还没有歌曲' : '${p.tracks.first.artist} 等',
            maxLines: 1,
            textAlign: center ? TextAlign.center : TextAlign.start,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5, color: FnColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Text('${p.tracks.length} 首',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textTertiary,
                )),
            _sep(),
            Text('$minutes 分钟',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textTertiary,
                )),
            _sep(),
            Text(p.createdAt ?? 'LOCAL',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: FnText.monoFamily.first,
                  color: FnColors.textTertiary,
                )),
          ],
        ),
      ],
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: FnColors.line2,
      );

  Widget _editBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 4, kFnPad, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.sm),
        border: Border.all(color: FnColors.line),
      ),
      child: Row(
        children: [
          Text(
            '已选 ${_selected.length} 首',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: FnColors.textPrimary,
            ),
          ),
          const Spacer(),
          FnButton(
            label: '移出选中',
            icon: Icons.remove_circle_outline_rounded,
            variant: FnButtonVariant.coral,
            enabled: _selected.isNotEmpty,
            onTap: _removeSelected,
            size: FnButtonSize.sm,
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 0, kFnPad, 2),
      child: Row(
        children: [
          FnButton(
            label: '播放',
            icon: Icons.play_arrow_rounded,
            onTap: () => _play(false),
            size: FnButtonSize.sm,
          ),
          const SizedBox(width: 8),
          FnButton(
            label: '随机',
            icon: Icons.shuffle_rounded,
            variant: FnButtonVariant.soft,
            onTap: () => _play(true),
            size: FnButtonSize.sm,
          ),
          const Spacer(),
          if (fnBpOf(context) == FnBp.desktop) ...[
            FnButton(
              label: _editing ? '完成' : '批量',
              icon: _editing ? Icons.check_rounded : Icons.checklist_rounded,
              variant: FnButtonVariant.soft,
              onTap: () => setState(() {
                _editing = !_editing;
                if (!_editing) _selected.clear();
              }),
              size: FnButtonSize.sm,
            ),
            const SizedBox(width: 8),
          ],
          FnIconBtn(
            icon: Icons.add_rounded,
            onTap: _addSongs,
          ),
          const SizedBox(width: 8),
          FnIconBtn(
            icon: Icons.download_rounded,
            onTap: () => fnToast(context, '已下载歌单',
                icon: Icons.download_rounded),
          ),
        ],
      ),
    );
  }
}

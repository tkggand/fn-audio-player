import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../play_log.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';
import '../widgets/track_menu_sheet.dart';

/// 播放历史：统计 + 今天 / 昨天 / 更早分组，时间来自本地播放日志。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loading = true;
  String? _error;
  bool _cleared = false;

  List<Song> _songs = const [];
  Map<int, DateTime> _lastPlayed = const {};
  Set<int> _favIds = <int>{};

  int _todayPlays = 0;
  int _weekPlays = 0;
  int _weekSeconds = 0;

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
        ApiClient.instance.fetchHistory(limit: 100),
        PlayLog.instance.lastPlayedBySong(),
        PlayLog.instance.weekCounts(),
        PlayLog.instance.weekSummary(),
        ApiClient.instance.fetchFavorites(),
      ]);
      final songs = res[0] as List<Song>;
      final played = res[1] as Map<int, DateTime>;
      final weekCounts = res[2] as List<int>;
      final summary = res[3] as ({int plays, int seconds, String? topArtist});
      final favs = res[4] as List<Song>;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var todayPlays = 0;
      played.forEach((_, ts) {
        if (!ts.isBefore(today)) todayPlays++;
      });

      if (!mounted) return;
      setState(() {
        _songs = songs;
        _lastPlayed = played;
        _todayPlays = todayPlays;
        _weekPlays = weekCounts.fold(0, (a, b) => a + b);
        _weekSeconds = summary.seconds;
        _favIds = favs.map((s) => s.id).toSet();
        _cleared = false;
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

  String _dayKey(int id) {
    final ts = _lastPlayed[id];
    if (ts == null) return '更早';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!ts.isBefore(today)) return '今天';
    if (!ts.isBefore(today.subtract(const Duration(days: 1)))) return '昨天';
    return '更早';
  }

  String? _timeOf(int id) {
    final ts = _lastPlayed[id];
    if (ts == null) return null;
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int get _artistCount => _songs.map((s) => s.artist).toSet().length;

  void _playToday(bool shuffle) {
    final today = _songs.where((s) => _dayKey(s.id) == '今天').toList();
    final pool = today.isNotEmpty ? today : _songs.take(8).toList();
    if (pool.isEmpty) {
      fnToast(context, '没有可播放的记录', icon: Icons.info_outline_rounded);
      return;
    }
    final list = [...pool];
    if (shuffle) list.shuffle();
    PlayerController.instance.playList(list, 0);
    fnToast(context, shuffle ? '随机播放历史' : '重播今天',
        icon: shuffle ? Icons.shuffle_rounded : Icons.play_arrow_rounded);
  }

  Future<void> _clear() async {
    if (_songs.isEmpty && !_loading) {
      fnToast(context, '历史已经是空的', icon: Icons.info_outline_rounded);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('清空播放历史？', style: TextStyle(fontSize: 17)),
        content: Text(
          '将移除本地记录与统计，不会影响收藏和歌单。',
          style: TextStyle(fontSize: 13, color: FnColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: FnColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: FnColors.coral)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PlayLog.instance.clear();
      if (!mounted) return;
      setState(() {
        _cleared = true;
        _songs = const [];
        _lastPlayed = const {};
        _todayPlays = 0;
        _weekPlays = 0;
        _weekSeconds = 0;
      });
      fnToast(context, '播放历史已清空', icon: Icons.delete_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Center(
                    child: FnEmpty(
                      icon: CupertinoIcons.exclamationmark_circle,
                      title: '历史加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      FnNav(
                        title: '播放历史',
                        subtitle: 'HISTORY',
                        trailing: [
                          FnIconBtn(
                            icon: CupertinoIcons.trash,
                            variant: FnIconBtnVariant.plain,
                            onTap: _clear,
                          ),
                        ],
                      ),
                      _stats(),
                      _toolbar(),
                      ..._groups(),
                      FnPageFoot(
                        left: _cleared || _songs.isEmpty
                            ? 'HISTORY · EMPTY'
                            : '${_songs.length} 条记录 · LAST 30 DAYS',
                        right: '隐私设置',
                        onRight: () => context.push('/settings'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _stats() {
    final hours = _weekSeconds / 3600;
    return Padding(
      padding: EdgeInsets.fromLTRB(fnPagePad(context), 12, fnPagePad(context), 4),
      child: Row(
        children: [
          Expanded(
            child: FnStatTile(
              value: '$_todayPlays',
              label: '今天播放',
              highlight: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FnStatTile(value: '$_weekPlays', label: '本周曲目'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FnStatTile(
              value: hours >= 1
                  ? '${hours.toStringAsFixed(1)}h'
                  : '${(_weekSeconds / 60).round()}m',
              label: '本周时长',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FnStatTile(value: '$_artistCount', label: '不同艺人'),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(fnPagePad(context), 8, fnPagePad(context), 4),
      child: Row(
        children: [
          FnButton(
            label: '重播今天',
            icon: Icons.play_arrow_rounded,
            onTap: () => _playToday(false),
            size: FnButtonSize.sm,
          ),
          const SizedBox(width: 8),
          FnButton(
            label: '随机',
            icon: Icons.shuffle_rounded,
            variant: FnButtonVariant.soft,
            onTap: () => _playToday(true),
            size: FnButtonSize.sm,
          ),
          const Spacer(),
          FnChip(
            label: '最新',
            icon: CupertinoIcons.clock,
            selected: true,
            small: true,
            onTap: () => fnToast(context, '已按时间倒序',
                icon: Icons.sort_rounded),
          ),
        ],
      ),
    );
  }

  List<Widget> _groups() {
    if (_cleared || _songs.isEmpty) {
      return [
        FnEmpty(
          icon: CupertinoIcons.time,
          title: '还没有播放记录',
          message: '播放过的歌曲会出现在这里，方便你重新找回。',
          actionLabel: '去发现音乐',
          onAction: () {
            Navigator.of(context).maybePop();
          },
        ),
      ];
    }
    final widgets = <Widget>[];
    for (final key in const ['今天', '昨天', '更早']) {
      final list = _songs.where((s) => _dayKey(s.id) == key).toList();
      if (list.isEmpty) continue;
      widgets.add(
        Padding(
          padding: EdgeInsets.fromLTRB(fnPagePad(context), 20, fnPagePad(context), 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(key, style: FnTextStyles.of(context).h3),
              ),
              Text('${list.length} TRACKS',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: FnText.monoFamily.first,
                    color: FnColors.textTertiary,
                  )),
            ],
          ),
        ),
      );
      if (fnBpOf(context) == FnBp.desktop) {
        widgets.add(
          FnSongTable(
            songs: list,
            favoriteIds: _favIds,
            currentId: PlayerController.instance.current?.id,
            isPlaying: PlayerController.instance.isPlaying,
            onPlay: (i) {
              PlayerController.instance.playList(list, i);
            },
            onMore: (i) => showTrackMenu(
              context,
              list[i],
              isFavorite: _favIds.contains(list[i].id),
              onFavoriteChanged: () => _load(),
            ),
            onFavorite: (i) => _toggleFav(list[i]),
          ),
        );
        continue;
      }
      for (var i = 0; i < list.length; i++) {
        final song = list[i];
        final time = _timeOf(song.id);
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kFnPad - 8),
            child: FnSongRow(
              song: song,
              showDuration: time == null,
              trailing: time == null
                  ? null
                  : Text(time,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: FnText.monoFamily.first,
                        color: FnColors.textTertiary,
                      )),
              isCurrent: PlayerController.instance.current?.id == song.id,
              isPlaying: PlayerController.instance.isPlaying,
              onTap: () {
                PlayerController.instance.playList(list, i);
              },
              onMore: () => showTrackMenu(
                context,
                song,
                isFavorite: _favIds.contains(song.id),
                onFavoriteChanged: () => _load(),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _toggleFav(Song song) async {
    final fav = _favIds.contains(song.id);
    try {
      if (fav) {
        await ApiClient.instance.removeFavorite(song.id);
      } else {
        await ApiClient.instance.addFavorite(song.id);
      }
      setState(() {
        if (fav) {
          _favIds.remove(song.id);
        } else {
          _favIds.add(song.id);
        }
      });
      if (!mounted) return;
      fnToast(context, fav ? '已取消收藏' : '已收藏 ${song.title}');
    } catch (e) {
      if (mounted) fnToast(context, '操作失败：$e');
    }
  }
}

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/fn_ui.dart';
import '../widgets/quality_sheet.dart';
import '../widgets/track_menu_sheet.dart';

/// 听歌 · 沉浸式竖向流。
///
/// 一屏一首：模糊封面背景 + 大幅封面 + 曲目信息 + 竖向动作栏 + 进度与传输控制。
/// 上滑切换下一首并立即播放；播放源与全局 PlayerController 队列保持同步。
class ListenPage extends StatefulWidget {
  const ListenPage({super.key});

  @override
  State<ListenPage> createState() => _ListenPageState();
}

class _ListenPageState extends State<ListenPage> with FnThemeAware<ListenPage> {
  final _pc = PlayerController.instance;
  final _pageController = PageController();

  List<Song> _songs = const [];
  Set<int> _favIds = <int>{};
  bool _loading = true;
  String? _error;

  int _page = 0;
  String _roamMode = 'private';
  String? _lyricLine;
  Timer? _ticker;
  bool _hintHidden = false;

  static const _roamModes = [
    ('private', '私人漫游', '按你的口味连续播放'),
    ('similar', '相似歌曲', '沿着当前这首歌继续'),
    ('random', '随机漫游', '跳出熟悉，偶遇新声音'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hintHidden = true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.instance.fetchSongs(),
        ApiClient.instance.fetchFavorites(),
      ]);
      final favs = results[1];
      final songList = _pc.queue.isNotEmpty ? _pc.queue : results[0];
      if (songList.isEmpty) {
        if (mounted) {
          setState(() {
            _songs = const [];
            _loading = false;
          });
        }
        return;
      }
      final ids = songList.map((s) => s.id).toList();
      final cur = _pc.current?.id;
      var start = cur == null ? 0 : ids.indexOf(cur);
      if (start < 0) start = 0;
      final order = [...ids.sublist(start), ...ids.sublist(0, start)];
      final byId = {for (final s in songList) s.id: s};
      if (mounted) {
        setState(() {
          _songs = order.map((id) => byId[id]!).toList();
          _favIds = favs.map((s) => s.id).toSet();
          _page = 0;
          _loading = false;
        });
      }
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      _loadLyric(_songs.first);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadLyric(Song song) async {
    if (mounted) setState(() => _lyricLine = null);
    if (!song.hasLyric) return;
    try {
      final data = await ApiClient.instance.fetchLyric(song.id);
      final line = data.lines.isEmpty ? null : data.lines.first.text;
      if (mounted && _songs.isNotEmpty && _songs[_page].id == song.id) {
        setState(() => _lyricLine = line);
      }
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    setState(() {
      _page = index;
      _hintHidden = true;
    });
    final song = _songs[index];
    _loadLyric(song);
    if (_pc.current?.id != song.id) {
      _pc.playList(_songs, index);
      ApiClient.instance.recordHistory(song.id).catchError((_) {});
    }
  }

  Future<void> _toggleFav(Song song) async {
    final on = _favIds.contains(song.id);
    setState(() {
      if (on) {
        _favIds.remove(song.id);
      } else {
        _favIds.add(song.id);
      }
    });
    try {
      if (on) {
        await ApiClient.instance.removeFavorite(song.id);
      } else {
        await ApiClient.instance.addFavorite(song.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (on) {
          _favIds.add(song.id);
        } else {
          _favIds.remove(song.id);
        }
      });
      fnToast(context, '收藏失败：$e');
    }
  }

  void _openRoamSheet() {
    showFnSheet<void>(
      context,
      eyebrow: 'ROAM',
      title: '漫游模式',
      subtitle: '沿着你的听歌习惯，不间断地发现下一首',
      children: [
        for (final m in _roamModes)
          FnOptionRow(
            title: m.$2,
            subtitle: m.$3,
            icon: m.$1 == 'private'
                ? Icons.auto_awesome
                : m.$1 == 'similar'
                    ? CupertinoIcons.waveform
                    : Icons.shuffle_rounded,
            on: _roamMode == m.$1,
            onTap: () {
              Navigator.pop(context);
              setState(() => _roamMode = m.$1);
              fnToast(context, '已切换到${m.$2}');
              _pc.startRoam(m.$1, count: 20);
            },
          ),
      ],
    );
  }

  void _openMore(Song song) {
    showTrackMenu(context, song,
        isFavorite: _favIds.contains(song.id),
        onFavoriteChanged: () => _toggleFav(song));
  }

  void _next() {
    if (_page + 1 < _songs.length) {
      _pageController.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    } else {
      fnToast(context, '已到漫游末尾');
    }
  }

  void _prev() {
    if (_page > 0) {
      _pageController.animateToPage(
        _page - 1,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: fnDarkPalette.base,
        body: Center(
          child: FnEmpty(
            icon: CupertinoIcons.exclamationmark_circle,
            title: '加载失败',
            message: _error,
            actionLabel: '重试',
            onAction: _load,
            dark: true,
          ),
        ),
      );
    }
    if (_songs.isEmpty) {
      return Scaffold(
        backgroundColor: fnDarkPalette.base,
        body: Center(
          child: FnEmpty(
            icon: CupertinoIcons.music_note_list,
            title: '曲库还是空的',
            message: '先去「曲库」扫描本地音乐目录，再回来开始听歌。',
            actionLabel: '去扫描',
            onAction: () => context.push('/scan'),
            dark: true,
          ),
        ),
      );
    }
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // mobile 档底部有 AppShell 的 4 Tab，控件整体让开 Tab 高度；laptop 档为全屏流。
    final tabTop = safeBottom + (fnBpOf(context).isMobile ? kFnTabH : 0) + 8;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _songs.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final song = _songs[index];
              final active = index == _page;
              return _FeedItem(
                song: song,
                index: index,
                active: active,
                liked: _favIds.contains(song.id),
                isCurrent: _pc.current?.id == song.id,
                playing: _pc.isPlaying,
                position: _pc.positionSec,
                duration: _pc.durationSec,
                lyric: active ? _lyricLine : null,
                roamLabel: _roamModes
                    .firstWhere((m) => m.$1 == _roamMode).$2,
                roamIcon: _roamMode == 'private'
                    ? Icons.auto_awesome
                    : _roamMode == 'similar'
                        ? CupertinoIcons.waveform
                        : Icons.shuffle_rounded,
                shuffle: _pc.shuffle,
                repeat: _pc.repeat,
                tabTop: tabTop,
                onRoam: _openRoamSheet,
                onPlay: () {
                  if (_pc.current?.id == song.id) {
                    _pc.togglePlay();
                  } else {
                    _pc.playList(_songs, index);
                    ApiClient.instance.recordHistory(song.id).catchError((_) {});
                  }
                },
                onPrev: _prev,
                onNext: _next,
                onFav: () => _toggleFav(song),
                onAdd: () => showTrackMenu(context, song,
                    isFavorite: _favIds.contains(song.id),
                    onFavoriteChanged: () => _toggleFav(song)),
                onQuality: () async {
                  final q = await openQualitySheet(context, current: _pc.quality);
                  if (q != null) await _pc.setQuality(q);
                },
                onShare: () =>
                    fnToast(context, '播放链接已复制', icon: Icons.link_rounded),
                onMore: () => _openMore(song),
                onSeek: (v) => _pc.seek(v),
              );
            },
          ),
          // 上滑提示
          Positioned(
            left: 0,
            right: 0,
            bottom: tabTop + 8,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: _hintHidden ? 0 : 1,
                child: Column(
                  children: [
                    Icon(CupertinoIcons.chevron_up,
                        size: 16, color: Colors.white.withValues(alpha: 0.38)),
                    const SizedBox(height: 1),
                    Text(
                      '上滑换歌',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.72,
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedItem extends StatelessWidget {
  const _FeedItem({
    required this.song,
    required this.index,
    required this.active,
    required this.liked,
    required this.isCurrent,
    required this.playing,
    required this.position,
    required this.duration,
    required this.lyric,
    required this.roamLabel,
    required this.roamIcon,
    required this.shuffle,
    required this.repeat,
    required this.tabTop,
    required this.onRoam,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
    required this.onFav,
    required this.onAdd,
    required this.onQuality,
    required this.onShare,
    required this.onMore,
    required this.onSeek,
  });

  final Song song;
  final int index;
  final bool active;
  final bool liked;
  final bool isCurrent;
  final bool playing;
  final double position;
  final double duration;
  final String? lyric;
  final String roamLabel;
  final IconData roamIcon;
  final bool shuffle;
  final LoopMode repeat;
  final double tabTop;
  final VoidCallback onRoam;
  final VoidCallback onPlay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFav;
  final VoidCallback onAdd;
  final VoidCallback onQuality;
  final VoidCallback onShare;
  final VoidCallback onMore;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final hue = fnHue(song.id).toDouble();
    final fmt = fnFormatOf(song);
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 模糊封面舞台
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF050506),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
                    child: Transform.scale(
                      scale: 1.18,
                      child: Image.network(
                        ApiClient.instance.coverUrl(song.id),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => DecoratedBox(
                          decoration:
                              BoxDecoration(gradient: fnCoverGradient(song.id)),
                        ),
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.24),
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.58),
                          const Color(0xFF050506),
                        ],
                        stops: const [0, 0.34, 0.72, 1],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.55),
                        radius: 0.65,
                        colors: [
                          HSLColor.fromAHSL(0.18, hue, 0.65, 0.42).toColor(),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 顶部：漫游胶囊 + 音质 + 更多
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: onRoam,
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: fnDarkPalette.lime,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Icon(roamIcon, size: 13, color: fnDarkPalette.lime),
                              const SizedBox(width: 5),
                              Text(
                                roamLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(CupertinoIcons.chevron_down,
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: fnDarkPalette.lime.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: fnDarkPalette.lime.withValues(alpha: 0.22)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                  color: fnDarkPalette.lime,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${fmt.label} · ${fmt.codec}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.36,
                                fontFamily: 'monospace',
                                color: fnDarkPalette.lime,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _DarkIconBtn(icon: Icons.more_vert, onTap: onMore),
                    ],
                  ),
                ),
                // 封面
                Expanded(
                  child: Center(
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      scale: active ? 1 : 0.97,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final size = MediaQuery.sizeOf(context);
                          final side = (size.width * 0.74).clamp(180.0, 320.0);
                          return Container(
                            width: side,
                            height: side,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 46,
                                  offset: const Offset(0, 22),
                                ),
                                BoxShadow(
                                  color: HSLColor.fromAHSL(
                                          0.32, hue, 0.7, 0.5)
                                      .toColor(),
                                  blurRadius: 60,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: FnCover(
                                songId: song.id, size: side, radius: 20),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                // 文案
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 88, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 8.5,
                              letterSpacing: 1.36,
                              fontFamily: 'monospace',
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                          Container(
                            width: 16,
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          Text(
                            (song.genre ?? '未知风格').toUpperCase(),
                            style: TextStyle(
                              fontSize: 8.5,
                              letterSpacing: 1.36,
                              fontFamily: 'monospace',
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (MediaQuery.sizeOf(context).width * 0.076)
                              .clamp(25.0, 33.0),
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -(MediaQuery.sizeOf(context).width * 0.076)
                                  .clamp(25.0, 33.0) *
                              0.045,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.86),
                              ),
                            ),
                          ),
                          const _Dot(),
                          Flexible(
                            child: Text(
                              song.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                            ),
                          ),
                          const _Dot(),
                          Text(
                            song.year?.toString() ?? '----',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.58),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Icon(CupertinoIcons.text_quote,
                              size: 13, color: fnDarkPalette.lime),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              lyric ?? '暂无歌词 · 轻点封面查看歌词',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 底部：进度 + 传输
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, tabTop + 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              fmtDuration(isCurrent ? position : 0),
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: Colors.white.withValues(alpha: 0.48),
                              ),
                            ),
                          ),
                          Expanded(
                            child: FnScrubber(
                              position: isCurrent ? position : 0,
                              duration: duration > 0
                                  ? duration
                                  : (song.duration ?? 0),
                              onSeek: onSeek,
                              height: 18,
                              trackHeight: 2,
                              timeStyle: const TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            child: Text(
                              fmtDuration(song.duration),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: Colors.white.withValues(alpha: 0.48),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _FeedBtn(
                            icon: Icons.shuffle_rounded,
                            on: shuffle,
                            onTap: () {
                              PlayerController.instance.toggleShuffle();
                            },
                            toast: shuffle ? '随机播放已关闭' : '随机播放已开启',
                            context: context,
                          ),
                          _FeedBtn(
                            icon: CupertinoIcons.backward_end_fill,
                            onTap: onPrev,
                          ),
                          GestureDetector(
                            onTap: onPlay,
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: fnDarkPalette.lime,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        fnDarkPalette.lime.withValues(alpha: 0.5),
                                    blurRadius: 30,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Icon(
                                isCurrent && playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 26,
                                color: fnDarkPalette.limeInk,
                              ),
                            ),
                          ),
                          _FeedBtn(
                            icon: CupertinoIcons.forward_end_fill,
                            onTap: onNext,
                          ),
                          _FeedBtn(
                            icon: repeat == LoopMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            on: repeat != LoopMode.off,
                            onTap: () {
                              PlayerController.instance.cycleRepeat();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 右侧竖向动作栏
          Positioned(
            right: 13,
            bottom: tabTop + 128,
            child: Column(
              children: [
                _RailBtn(
                  icon: liked
                      ? CupertinoIcons.heart_fill
                      : CupertinoIcons.heart,
                  label: '喜欢',
                  active: liked,
                  activeColor: fnDarkPalette.coral,
                  activeBg: fnDarkPalette.coralSoft,
                  onTap: onFav,
                ),
                const SizedBox(height: 15),
                _RailBtn(
                  icon: Icons.queue_music_rounded,
                  label: '歌单',
                  onTap: onAdd,
                ),
                const SizedBox(height: 15),
                _RailBtn(
                  icon: Icons.graphic_eq_rounded,
                  label: fmt.label == 'LOSSY' ? '256k' : '无损',
                  onTap: onQuality,
                ),
                const SizedBox(height: 15),
                _RailBtn(
                  icon: CupertinoIcons.share,
                  label: '分享',
                  onTap: onShare,
                ),
                const SizedBox(height: 15),
                _RailBtn(
                  icon: Icons.more_horiz,
                  label: '更多',
                  onTap: onMore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkIconBtn extends StatelessWidget {
  const _DarkIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _RailBtn extends StatelessWidget {
  const _RailBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
    this.activeBg,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;
  final Color? activeBg;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: active
                    ? (activeBg ?? fnDarkPalette.coralSoft)
                    : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? (activeColor ?? fnDarkPalette.coral)
                          .withValues(alpha: 0.34)
                      : Colors.white.withValues(alpha: 0.13),
                ),
              ),
              child: Icon(
                icon,
                size: 19,
                color: active
                    ? (activeColor ?? fnDarkPalette.coral)
                    : Colors.white.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.56),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedBtn extends StatelessWidget {
  const _FeedBtn({
    required this.icon,
    required this.onTap,
    this.on = false,
    this.toast,
    this.context,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool on;
  final String? toast;
  final BuildContext? context;

  @override
  Widget build(BuildContext _) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        onTap();
        if (toast != null && context != null) fnToast(context!, toast!);
      },
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          icon,
          size: 20,
          color: on
              ? fnDarkPalette.lime
              : Colors.white.withValues(alpha: 0.74),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/fn_ui.dart';
import '../widgets/karaoke_lyrics.dart';
import '../widgets/quality_sheet.dart';
import '../widgets/signal_path_sheet.dart';
import '../widgets/spectrum.dart';
import '../widgets/track_menu_sheet.dart';

/// 正在播放（design/v3 pages/player.html）。
///
/// 结构严格对齐设计稿：
///   页头（收起 / FROM 每日推荐 / 更多）
///   封面 ⇄ 歌词横向双页（指示器点击或横滑切换）
///   信息（音质 / 音效 / 信号链路三个真实入口）
///   进度 + 走带（模式单钮循环 + 上一首 + 播放 + 下一首 + 播放列表）
///
/// 三档：mobile / laptop 单列全屏；desktop 封面左列 + 信息右列，
/// 歌词态横向铺满并隐藏信息列。本页恒为深色。
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  /// 0 = 封面，1 = 歌词。
  int _pane = 0;
  bool _lyricsVisited = false;
  bool _liked = false;
  int? _likeSongId;
  StreamSubscription<void>? _stateSub;
  List<DspPreset> _presets = const [];
  final PageController _pager = PageController();
  FnBp? _lastBp;

  @override
  void initState() {
    super.initState();
    _refreshLike();
    _loadPresets();
    // 切歌后收藏态跟随当前曲目（心形不应停留在上一首）。
    _stateSub = PlayerController.instance.stateChanges.stream.listen((_) {
      final song = PlayerController.instance.current;
      if (song != null && song.id != _likeSongId) _refreshLike();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bp = fnBpForWidth(MediaQuery.sizeOf(context).width);
    if (_lastBp != bp) {
      _lastBp = bp;
      // 跨断点时把横向分页同步到当前视图，避免从 desktop 歌词态缩回 laptop 后
      // 指示器显示歌词、分页却停在封面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pager.hasClients) _pager.jumpToPage(_pane);
      });
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _refreshLike() async {
    final song = PlayerController.instance.current;
    if (song == null) return;
    _likeSongId = song.id;
    try {
      final favs = await ApiClient.instance.fetchFavorites();
      if (!mounted || song.id != _likeSongId) return;
      setState(() => _liked = favs.any((s) => s.id == song.id));
    } catch (_) {}
  }

  Future<void> _loadPresets() async {
    try {
      final presets = await ApiClient.instance.fetchDspPresets();
      if (!mounted) return;
      setState(() => _presets = presets);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final song = PlayerController.instance.current;
    if (song == null) return;
    final next = !_liked;
    setState(() => _liked = next);
    try {
      if (next) {
        await ApiClient.instance.addFavorite(song.id);
      } else {
        await ApiClient.instance.removeFavorite(song.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _liked = !next);
      fnToast(context, '操作失败：$e');
    }
  }

  void _goPane(int pane) {
    final target = pane.clamp(0, 1).toInt();
    setState(() {
      _pane = target;
      if (target == 1) _lyricsVisited = true;
    });
    if (_lastBp != FnBp.desktop && _pager.hasClients) {
      _pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/discover');
    }
  }

  Future<void> _openQuality() async {
    final c = PlayerController.instance;
    final q = await openQualitySheet(context, current: c.quality);
    if (q == null) return;
    await c.setQuality(q);
    if (mounted) setState(() {});
  }

  Future<void> _openEffect() async {
    final c = PlayerController.instance;
    var presets = _presets;
    if (presets.isEmpty) {
      try {
        presets = await ApiClient.instance.fetchDspPresets();
        if (mounted) setState(() => _presets = presets);
      } catch (_) {}
    }
    if (!mounted) return;
    await showFnSheet(
      context,
      eyebrow: 'SOUND',
      title: '音效',
      subtitle: 'EQ 预设 · 与调音页联动',
      children: [
        FnOptionRow(
          icon: Icons.graphic_eq_rounded,
          title: '原声纯净',
          subtitle: '直通，无任何处理',
          on: c.presetId == null,
          onTap: () async {
            Navigator.of(context).pop();
            await c.setPreset(null);
            if (mounted) setState(() {});
          },
        ),
        for (final p in presets)
          FnOptionRow(
            icon: Icons.graphic_eq_rounded,
            title: p.name,
            subtitle: p.description ??
                (p.isSystem ? '系统预设' : '我的预设'),
            on: c.presetId == p.id,
            onTap: () async {
              Navigator.of(context).pop();
              await c.setPreset(p.id);
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }

  Future<void> _openSignalPath() async {
    var presets = _presets;
    if (presets.isEmpty) {
      try {
        presets = await ApiClient.instance.fetchDspPresets();
        if (mounted) setState(() => _presets = presets);
      } catch (_) {}
    }
    if (!mounted) return;
    await openSignalPath(context, presets: presets);
  }

  /// 播放列表弹层（v3 `playlistSheet`）：点击行切歌。
  Future<void> _openPlaylist() async {
    final c = PlayerController.instance;
    final queue = c.queue;
    if (queue.isEmpty) return;
    await showFnSheet(
      context,
      eyebrow: 'QUEUE',
      title: '播放列表',
      subtitle: '${queue.length} 首 · 点击切换',
      children: [
        for (var i = 0; i < queue.length; i++)
          _PlaylistRow(
            song: queue[i],
            index: i,
            current: i == c.index,
            onTap: () {
              Navigator.of(context).pop();
              c.playList(queue, i);
            },
          ),
      ],
    );
  }

  String _presetLabel() {
    final id = PlayerController.instance.presetId;
    if (id == null) return '原声纯净';
    for (final p in _presets) {
      if (p.id == id) return p.name;
    }
    return '#$id';
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return StreamBuilder<void>(
      stream: c.stateChanges.stream,
      builder: (context, _) {
        final song = c.current;
        if (song == null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [
                  const Center(
                    child: FnEmpty(
                      icon: CupertinoIcons.music_note,
                      title: '还没有正在播放的歌曲',
                      message: '从「听歌」选一首开始。',
                      dark: true,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 6,
                    child: FnIconBtn(
                      icon: CupertinoIcons.chevron_down,
                      variant: FnIconBtnVariant.dark,
                      onTap: _close,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final bp = fnBpForWidth(MediaQuery.sizeOf(context).width);
        final desktop = bp == FnBp.desktop;

        final body = GestureDetector(
          onVerticalDragEnd: bp == FnBp.mobile
              ? (d) {
                  if ((d.primaryVelocity ?? 0) > 280 &&
                      Navigator.of(context).canPop()) {
                    Navigator.of(context).maybePop();
                  }
                  if ((d.primaryVelocity ?? 0) < -280) {
                    context.push('/queue');
                  }
                }
              : null,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                FnStageBackground(song: song, blur: 42),
                SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      desktop ? _buildDesktop(context, song) : _buildCompact(song),
                      if (desktop)
                        Positioned(
                          left: 24,
                          top: 20,
                          child: FnIconBtn(
                            icon: CupertinoIcons.xmark,
                            variant: FnIconBtnVariant.dark,
                            tooltip: '关闭',
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // 本页恒为深色：状态栏图标固定浅色（iOS 刘海屏/Android 统一）。
          value: SystemUiOverlayStyle.light,
          child: body,
        );
      },
    );
  }

  // ---------------------------------------------------------------- 页头

  Widget _buildTopBar(Song song) {
    return Row(
      children: [
        FnIconBtn(
          icon: CupertinoIcons.chevron_down,
          variant: FnIconBtnVariant.dark,
          onTap: _close,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'FROM 每日推荐',
                style: TextStyle(
                  fontSize: 8,
                  fontFamily: FnText.monoFamily.first,
                  letterSpacing: 1.28,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '正在播放',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        FnIconBtn(
          icon: Icons.more_horiz,
          variant: FnIconBtnVariant.dark,
          onTap: () => showTrackMenu(
            context,
            song,
            isFavorite: _liked,
            onFavoriteChanged: _toggleLike,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ mobile/laptop

  Widget _buildCompact(Song song) {
    final bp = fnBpForWidth(MediaQuery.sizeOf(context).width);
    final hPad = bp == FnBp.laptop ? 34.0 : 22.0;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final narrow = bp == FnBp.laptop;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        hPad,
        bp == FnBp.laptop ? 10 : 2,
        hPad,
        (bp == FnBp.laptop ? 28 : 20) + bottom,
      ),
      child: Column(
        children: [
          _buildTopBar(song),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final side = _coverSideFor(bp, box.maxWidth, double.infinity);
                var stageH = side + 22;
                if (box.maxHeight.isFinite) {
                  stageH = math.min(stageH, box.maxHeight * 0.62);
                }
                stageH = stageH.clamp(160.0, 520.0).toDouble();
                // 上半区（封面 + 指示器）在页头与底部操作区之间居中，
                // 信息 / 进度 / 走带整块贴底（spaceBetween 把余量均分成两段空白）。
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(height: 16),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: stageH,
                              child: PageView(
                                controller: _pager,
                                onPageChanged: (i) => setState(() {
                                  _pane = i;
                                  if (i == 1) _lyricsVisited = true;
                                }),
                                children: [
                                  _CoverPane(song: song, bp: bp, side: side),
                                  _lyricsVisited
                                      ? _LyricsPane(song: song)
                                      : const SizedBox.shrink(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            _buildDots(desktop: false),
                          ],
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 22),
                            _center560(narrow, _buildInfo(song, desktop: false)),
                            // 频谱（Web 端在 mobile 隐藏，laptop/desktop 才显示）。
                            if (narrow) ...[
                              const SizedBox(height: 22),
                              _center560(
                                narrow,
                                const PlaybackSpectrum(
                                  height: 60,
                                  showAxis: false,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            _center560(narrow, _buildProgress(song)),
                            const SizedBox(height: 2),
                            _center560(narrow, _buildTransport()),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _center560(bool narrow, Widget child) {
    if (!narrow) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------- desktop

  Widget _buildDesktop(BuildContext context, Song song) {
    final lyricsMode = _pane == 1;

    return LayoutBuilder(
      builder: (context, box) {
        final stageH =
            math.min(box.maxHeight * 0.56, 500.0).clamp(320.0, 500.0).toDouble();

        Widget lyricStage() => GestureDetector(
              onHorizontalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 250) _goPane(0);
              },
              child: SizedBox(height: stageH, child: _LyricsPane(song: song)),
            );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  // 中轴单列：封面 → 封面/歌词切换 → 标题 → 歌手·专辑 → 音质/音效/信号路径。
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (lyricsMode) ...[
                        lyricStage(),
                        const SizedBox(height: 16),
                        _buildDots(desktop: true),
                      ] else ...[
                        GestureDetector(
                          onHorizontalDragEnd: (d) {
                            if ((d.primaryVelocity ?? 0) < -250) _goPane(1);
                          },
                          child: SizedBox(
                            width: 320,
                            height: 320,
                            child: _CoverPane(song: song, bp: FnBp.desktop),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildDots(desktop: true),
                        const SizedBox(height: 22),
                        _buildInfo(song, desktop: true),
                        // 频谱：与 Web 端 NowPlaying 右列底部的 dt-spec 同位。
                        const SizedBox(height: 28),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: const PlaybackSpectrum(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 44),
                      _buildProgress(song),
                      const SizedBox(height: 18),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _buildTransport(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- 指示器

  Widget _buildDots({required bool desktop}) {
    if (!desktop) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 2; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goPane(i),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    width: _pane == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _pane == i
                          ? fnDarkPalette.lime
                          : Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segLabel('封面', 0),
          _segLabel('歌词', 1),
        ],
      ),
    );
  }

  Widget _segLabel(String label, int pane) {
    final on = _pane == pane;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _goPane(pane),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.white.withValues(alpha: 0.13) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : Colors.white.withValues(alpha: 0.62),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 信息

  Widget _buildInfo(Song song, {required bool desktop}) {
    final titleSize = desktop ? 26.0 : (MediaQuery.sizeOf(context).width >= kFnBpLaptop ? 30.0 : 25.0);

    final copy = Column(
      crossAxisAlignment:
          desktop ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          textAlign: desktop ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            height: 1.14,
            fontWeight: FontWeight.w700,
            letterSpacing: desktop ? -1.04 : -1.0,
            color: Colors.white,
          ),
        ),
        SizedBox(height: desktop ? 6 : 4),
        Text(
          song.artist.isEmpty ? song.album : '${song.artist} · ${song.album}',
          textAlign: desktop ? TextAlign.center : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: desktop ? 14 : (MediaQuery.sizeOf(context).width >= kFnBpLaptop ? 13.5 : 12),
            color: desktop
                ? fnDarkPalette.coral
                : Colors.white.withValues(alpha: 0.56),
          ),
        ),
        SizedBox(height: desktop ? 16 : 9),
        // 音质 / 音效 / 信号路径：三档固定同一行，音效名过长时省略。
        Row(
          mainAxisSize: desktop ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _qualityTag(desktop: desktop),
            SizedBox(width: desktop ? 10 : 7),
            Flexible(child: _effectTag(desktop: desktop)),
            SizedBox(width: desktop ? 10 : 7),
            _signalDot(),
          ],
        ),
      ],
    );

    final like = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleLike,
      child: SizedBox(
        width: desktop ? 30 : 30,
        height: desktop ? 30 : 30,
        child: Icon(
          _liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          size: 20,
          color: fnDarkPalette.coral,
        ),
      ),
    );

    if (desktop) return copy;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: copy),
        const SizedBox(width: 12),
        like,
      ],
    );
  }

  Widget _qualityTag({required bool desktop}) {
    final c = PlayerController.instance;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openQuality,
      child: Container(
        height: desktop ? 26 : 19,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: fnDarkPalette.green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
        ),
        // widthFactor: 1 让标签按文字宽度收敛，不被 Row 拉满整行。
        child: Align(
          alignment: Alignment.center,
          widthFactor: 1,
          child: Text(
            qualityLabel(context, c.quality),
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.34,
              fontFamily: FnText.monoFamily.first,
              color: fnDarkPalette.green,
            ),
          ),
        ),
      ),
    );
  }

  Widget _effectTag({required bool desktop}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openEffect,
      child: Container(
        height: desktop ? 26 : null,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Align(
          alignment: Alignment.center,
          widthFactor: 1,
          child: Text(
            '音效 · ${_presetLabel()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontFamily: FnText.monoFamily.first,
              letterSpacing: 0.18,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signalDot() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openSignalPath,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: fnDarkPalette.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: fnDarkPalette.green.withValues(alpha: 0.18),
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: fnDarkPalette.green.withValues(alpha: 0.85),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 进度 / 走带

  Widget _buildProgress(Song song) {
    final c = PlayerController.instance;
    return FnScrubber(
      position: c.positionSec,
      duration: c.durationSec > 0 ? c.durationSec : (song.duration ?? 0),
      buffered: c.bufferedSec,
      onSeek: c.seek,
      trackColor: Colors.white.withValues(alpha: 0.18),
      timeStyle: TextStyle(
        fontSize: 9.5,
        fontFamily: FnText.monoFamily.first,
        color: Colors.white.withValues(alpha: 0.46),
      ),
    );
  }

  Widget _buildTransport() {
    final c = PlayerController.instance;
    final mode = c.playMode;
    final modeIcon = switch (mode) {
      'shuffle' => Icons.shuffle_rounded,
      'one' => Icons.repeat_one_rounded,
      _ => Icons.repeat_rounded,
    };
    final modeLabel = switch (mode) {
      'shuffle' => '随机播放',
      'one' => '循环一次',
      _ => '列表循环',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Tooltip(
            message: modeLabel,
            waitDuration: const Duration(milliseconds: 400),
            child: _tButton(
              icon: modeIcon,
              on: mode != 'all',
              onTap: c.cyclePlayMode,
              size: 22,
            ),
          ),
          _tButton(
            icon: CupertinoIcons.backward_end_fill,
            iconSize: 24,
            onTap: c.prev,
          ),
          GestureDetector(
            onTap: c.togglePlay,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: fnDarkPalette.lime,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: fnDarkPalette.lime.withValues(alpha: 0.5),
                    blurRadius: 38,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Icon(
                c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
                color: fnDarkPalette.limeInk,
              ),
            ),
          ),
          _tButton(
            icon: CupertinoIcons.forward_end_fill,
            iconSize: 24,
            onTap: c.next,
          ),
          _tButton(
            icon: Icons.queue_music_rounded,
            onTap: _openPlaylist,
            size: 23,
          ),
        ],
      ),
    );
  }

  Widget _tButton({
    required IconData icon,
    required VoidCallback onTap,
    bool on = false,
    double size = 44,
    double iconSize = 23,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          size: iconSize,
          color: on
              ? fnDarkPalette.lime
              : Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

// ==================================================================== 舞台

/// 封面边长：三档同一套收敛规则（design/v3 `.cover-art` clamp 与 laptop/desktop 覆写）。
double _coverSideFor(FnBp bp, double maxWidth, double maxHeight) {
  double side;
  if (bp == FnBp.desktop) {
    side = 320;
  } else if (bp == FnBp.laptop) {
    side = math.min(maxWidth * 0.52, 360);
  } else {
    side = (maxWidth * 0.68).clamp(216.0, 296.0).toDouble();
  }
  if (maxHeight.isFinite) side = math.min(side, maxHeight * 0.94);
  return side.clamp(120.0, 500.0).toDouble();
}

/// 封面舞台：氛围光 + 大封面（尺寸随断点与可用空间收敛）。
class _CoverPane extends StatelessWidget {
  const _CoverPane({required this.song, required this.bp, this.side});

  final Song song;
  final FnBp bp;
  final double? side;

  @override
  Widget build(BuildContext context) {
    final hue = fnHue(song.id).toDouble();
    return LayoutBuilder(
      builder: (context, box) {
        final s = _coverSideFor(bp, box.maxWidth, box.maxHeight);
        final coverSide = side == null ? s : math.min(side!, s);
        final radius = bp == FnBp.laptop ? 26.0 : 22.0;
        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: coverSide * 0.9,
                height: coverSide * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      HSLColor.fromAHSL(0.34, hue, 0.7, 0.52).toColor(),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.68],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.85),
                      blurRadius: 70,
                      offset: const Offset(0, 34),
                    ),
                  ],
                ),
                child: FnCover(
                  songId: song.id,
                  size: coverSide,
                  radius: radius,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LyricsPane extends StatelessWidget {
  const _LyricsPane({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return KaraokeLyrics(songId: song.id);
  }
}

// ==================================================================== 播放列表行

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.song,
    required this.index,
    required this.current,
    required this.onTap,
  });

  final Song song;
  final int index;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: current ? FnColors.limeSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Center(
                child: current
                    ? Icon(Icons.play_arrow_rounded,
                        size: 12, color: FnColors.limeText)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: FnText.monoFamily.first,
                          color: FnColors.textTertiary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            FnCover(songId: song.id, size: 34, radius: 7),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: current ? FnColors.limeText : FnColors.textPrimary,
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: FnColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fmtDuration(song.duration),
              style: TextStyle(
                fontSize: 10,
                fontFamily: FnText.monoFamily.first,
                color: FnColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

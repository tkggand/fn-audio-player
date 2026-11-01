import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/fn_ui.dart';

/// 歌词：随播放滚动的高亮歌词 + 翻译/偏移/字号 + 底部进度与传输。
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key, required this.songId, this.songTitle = ''});

  final int songId;
  final String songTitle;

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final _scroll = ScrollController();
  LyricData? _data;
  bool _loading = true;
  String? _error;
  bool _showTranslation = false;
  double _offset = 0;
  double _fontSize = 20;
  bool _fontSized = false;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _load();
    PlayerController.instance.stateChanges.stream.listen((_) => _sync());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.fetchLyric(widget.songId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      _sync();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  int _indexAt(double posMs) {
    final lines = _data?.lines ?? const <LyricLine>[];
    if (lines.isEmpty) return -1;
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].timeMs;
      if (t == null) continue;
      if (t <= posMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _sync() {
    final c = PlayerController.instance;
    if (c.current?.id != widget.songId || _data == null) return;
    if (!mounted) return;
    final idx = _indexAt(c.positionSec * 1000 + _offset * 1000);
    if (idx == _active) {
      // 扫色进度依赖播放位置，激活行需要随播放刷新。
      setState(() {});
      return;
    }
    setState(() => _active = idx);
    _autoScroll(idx);
  }

  void _autoScroll(int idx) {
    if (!_scroll.hasClients || idx < 0) return;
    final target = (idx * (_fontSize * 2.1 + 16) - 140).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// 激活行扫色进度：当前播放位置在本行时长区间内的比例。
  double _progressOf(int i, List<LyricLine> lines, double offset) {
    final line = lines[i];
    final start = line.timeMs;
    if (start == null) return 0;
    final next = i + 1 < lines.length ? lines[i + 1].timeMs : null;
    final span = (next != null && next > start) ? (next - start) : 3000;
    final pos = PlayerController.instance.positionSec * 1000 + offset * 1000;
    return ((pos - start) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // 三档字号（design/v3 §4 lyrics）：mobile 20 / laptop 26 / desktop 32。
    if (!_fontSized) {
      _fontSize = switch (fnBpOf(context)) {
        FnBp.mobile => 20,
        FnBp.laptop => 26,
        FnBp.desktop => 32,
      };
      _fontSized = true;
    }
    final song = PlayerController.instance.current;
    final lines = _data?.lines ?? const <LyricLine>[];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (song != null)
            FnStageBackground(song: song)
          else
            const ColoredBox(color: Color(0xFF07080A)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  child: Row(
                    children: [
                      FnIconBtn(
                        icon: CupertinoIcons.chevron_down,
                        variant: FnIconBtnVariant.dark,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              song?.title ?? widget.songTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              song?.artist ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FnIconBtn(
                        icon: Icons.more_horiz,
                        variant: FnIconBtnVariant.dark,
                        onTap: () => fnToast(context, '长按歌词可复制'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      if (_loading)
                        const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else if (_error != null)
                        Center(
                          child: FnEmpty(
                            icon: CupertinoIcons.exclamationmark_circle,
                            title: '歌词加载失败',
                            message: _error,
                            actionLabel: '重试',
                            onAction: _load,
                            dark: true,
                          ),
                        )
                      else if (lines.isEmpty)
                        Center(
                          child: FnEmpty(
                            icon: Icons.lyrics_outlined,
                            title: '暂无歌词',
                            message: '可以在「曲库 · 歌曲菜单」里导入 LRC 文件。',
                            color: fnDarkPalette.lime,
                            dark: true,
                          ),
                        )
                      else
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 920),
                            child: ListView.builder(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(
                              30, MediaQuery.sizeOf(context).height * 0.16, 30,
                              MediaQuery.sizeOf(context).height * 0.24),
                          itemCount: lines.length,
                          itemBuilder: (context, i) {
                            final line = lines[i];
                            final on = i == _active;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 260),
                                style: TextStyle(
                                  fontSize: _fontSize,
                                  height: 1.45,
                                  fontWeight:
                                      on ? FontWeight.w600 : FontWeight.w600,
                                  letterSpacing: -0.3,
                                  color: on
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.38),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SweepText(
                                      text: line.text.isEmpty ? '♪' : line.text,
                                      active: on,
                                      progress: on
                                          ? _progressOf(i, lines, _offset)
                                          : 0,
                                      hue: (widget.songId * 53) % 360,
                                    ),
                                    if (_showTranslation)
                                      Text(
                                        '（翻译暂不可用）',
                                        style: TextStyle(
                                          fontSize: _fontSize * 0.6,
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: MediaQuery.sizeOf(context).height * 0.12,
                        height: 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.5),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(kFnPad, 4, kFnPad, 0),
                  child: Row(
                    children: [
                      FnChip(
                        label: '翻译',
                        selected: _showTranslation,
                        small: true,
                        onTap: () {
                          setState(() => _showTranslation = !_showTranslation);
                          fnToast(context,
                              _showTranslation ? '已开启翻译' : '已关闭翻译');
                        },
                      ),
                      const SizedBox(width: 7),
                      FnChip(
                        label: '偏移 ${_offset.toStringAsFixed(1)}s',
                        selected: _offset != 0,
                        small: true,
                        onTap: () => _offsetSheet(),
                      ),
                      const Spacer(),
                      _FontBtn(
                        label: 'A-',
                        onTap: () => setState(
                            () => _fontSize = (_fontSize - 2).clamp(14, 44)),
                      ),
                      const SizedBox(width: 6),
                      _FontBtn(
                        label: 'A+',
                        onTap: () => setState(
                            () => _fontSize = (_fontSize + 2).clamp(14, 44)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kFnPad),
                  child: FnScrubber(
                    position: PlayerController.instance.positionSec,
                    duration: PlayerController.instance.durationSec,
                    onSeek: PlayerController.instance.seek,
                    timeStyle: TextStyle(
                      fontSize: 9.5,
                      fontFamily: FnText.monoFamily.first,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24,
                      10 + MediaQuery.paddingOf(context).bottom),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FnIconBtn(
                        icon: CupertinoIcons.backward_end_fill,
                        variant: FnIconBtnVariant.dark,
                        onTap: PlayerController.instance.prev,
                      ),
                      GestureDetector(
                        onTap: PlayerController.instance.togglePlay,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: fnDarkPalette.lime,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PlayerController.instance.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 26,
                            color: fnDarkPalette.limeInk,
                          ),
                        ),
                      ),
                      FnIconBtn(
                        icon: CupertinoIcons.forward_end_fill,
                        variant: FnIconBtnVariant.dark,
                        onTap: PlayerController.instance.next,
                      ),
                      FnIconBtn(
                        icon: CupertinoIcons.music_note_2,
                        variant: FnIconBtnVariant.dark,
                        onTap: () => context.pop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _offsetSheet() {
    showFnSheet<void>(
      context,
      eyebrow: 'LYRICS',
      title: '歌词偏移',
      subtitle: '让歌词与歌声对齐，每档 0.1 秒',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              FnButton(
                label: '-0.5s',
                size: FnButtonSize.sm,
                variant: FnButtonVariant.soft,
                onTap: () => setState(
                    () => _offset = (_offset - 0.5).clamp(-5.0, 5.0)),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_offset.toStringAsFixed(1)}s',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              FnButton(
                label: '+0.5s',
                size: FnButtonSize.sm,
                variant: FnButtonVariant.soft,
                onTap: () => setState(
                    () => _offset = (_offset + 0.5).clamp(-5.0, 5.0)),
              ),
            ],
          ),
        ),
        FnOptionRow(
          title: '重置偏移',
          icon: Icons.restart_alt_rounded,
          onTap: () {
            setState(() => _offset = 0);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _SweepText extends StatelessWidget {
  const _SweepText({
    required this.text,
    required this.active,
    required this.progress,
    required this.hue,
  });

  final String text;
  final bool active;
  final double progress;
  final int hue;

  @override
  Widget build(BuildContext context) {
    if (!active) return Text(text);
    final hueColor =
        HSLColor.fromAHSL(1, hue.toDouble(), 0.88, 0.66).toColor();
    final swept = progress.clamp(0.02, 0.98);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          hueColor,
          fnDarkPalette.lime,
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.42),
        ],
        stops: [0, swept, swept + 0.001, 1],
      ).createShader(rect),
      child: Text(
        text,
        style: TextStyle(
          shadows: [
            Shadow(color: fnDarkPalette.lime.withValues(alpha: 0.4), blurRadius: 22),
          ],
        ),
      ),
    );
  }
}

class _FontBtn extends StatelessWidget {
  const _FontBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

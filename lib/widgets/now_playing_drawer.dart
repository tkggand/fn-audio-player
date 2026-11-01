import 'package:flutter/material.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'fn_ui.dart';

/// laptop / desktop 档的 NowPlaying 右抽屉（design/v3 §8）。
///
/// - 宽度 380，自右侧滑出，底边让开播放条 72；
/// - 始终深色：内部令牌固定使用 [fnDarkPalette]，不随浅色主题变浅；
/// - 内容：封面氛围光 + 曲目信息 + 音质标签 + 3 行歌词预览 + 播放队列。
class NowPlayingDrawer extends StatefulWidget {
  const NowPlayingDrawer({
    super.key,
    required this.open,
    required this.onClose,
  });

  final bool open;
  final VoidCallback onClose;

  @override
  State<NowPlayingDrawer> createState() => _NowPlayingDrawerState();
}

class _NowPlayingDrawerState extends State<NowPlayingDrawer> {
  int? _lyricSongId;
  List<LyricLine> _lyrics = const [];

  Future<void> _loadLyrics(Song song) async {
    if (_lyricSongId == song.id) return;
    _lyricSongId = song.id;
    List<LyricLine> lines = const [];
    if (song.hasLyric) {
      try {
        final data = await ApiClient.instance.fetchLyric(song.id);
        lines = data.lines;
      } catch (_) {
        // 歌词拉取失败静默：预览区显示暂无歌词。
      }
    }
    if (!mounted || _lyricSongId != song.id) return;
    setState(() => _lyrics = lines);
  }

  @override
  Widget build(BuildContext context) {
    const p = fnDarkPalette;
    final c = PlayerController.instance;
    return IgnorePointer(
      ignoring: !widget.open,
      child: AnimatedSlide(
        offset: widget.open ? Offset.zero : const Offset(1, 0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Container(
          width: kFnDrawerW,
          decoration: const BoxDecoration(
            color: Color(0xF2121418),
            border: Border(left: BorderSide(color: Color(0x14FFFFFF))),
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 60,
                offset: Offset(-24, 0),
              ),
            ],
          ),
          child: StreamBuilder<void>(
            stream: c.stateChanges.stream,
            builder: (context, _) {
              final song = c.current;
              if (song != null) {
                // 歌词随曲目切换懒加载；构建期间只登记，不直接 setState。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _loadLyrics(song);
                });
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _head(),
                  Expanded(
                    child: song == null
                        ? Center(
                            child: Text(
                              '还没有正在播放的歌曲',
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textTertiary,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            children: [
                              _stage(song),
                              _meta(song),
                              _tags(song),
                              _lyricPreview(c),
                              _queue(c, song),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _head() {
    const p = fnDarkPalette;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          Text(
            '正在播放',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: p.textTertiary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(Icons.close_rounded, size: 18, color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(Song song) {
    final hue = fnHue(song.id).toDouble();
    return SizedBox(
      height: 244,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  HSLColor.fromAHSL(0.4, hue, 0.7, 0.52).toColor(),
                  Colors.transparent,
                ],
                stops: const [0, 0.68],
              ),
            ),
          ),
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xE0000000),
                  blurRadius: 60,
                  offset: Offset(0, 30),
                  spreadRadius: -22,
                ),
              ],
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: FnCover(songId: song.id, size: 220, radius: 18),
          ),
        ],
      ),
    );
  }

  Widget _meta(Song song) {
    const p = fnDarkPalette;
    return Column(
      children: [
        Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: p.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${song.artist} · ${song.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _tags(Song song) {
    const p = fnDarkPalette;
    final fmt = fnFormatOf(song);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 19,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: fmt.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              fmt.label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.34,
                fontFamily: FnText.monoFamily.first,
                color: fmt.color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${fmtSampleRate(song.sampleRate)} · ${song.bitDepth ?? '-'} bit',
            style: TextStyle(
              fontSize: 9,
              fontFamily: FnText.monoFamily.first,
              letterSpacing: 0.3,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyricPreview(PlayerController c) {
    const p = fnDarkPalette;
    final lines = _lyrics;
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SizedBox(
          height: 84,
          child: Center(
            child: Text(
              '暂无歌词',
              style: TextStyle(fontSize: 12, color: p.textTertiary),
            ),
          ),
        ),
      );
    }
    final ms = c.positionSec * 1000;
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      if (ms >= (lines[i].timeMs ?? 0)) idx = i;
    }
    final maxStart = lines.length > 3 ? lines.length - 3 : 0;
    final start = (idx - 1).clamp(0, maxStart).toInt();
    final rows = <Widget>[];
    for (var i = 0; i < 3; i++) {
      final lineIdx = start + i;
      final has = lineIdx < lines.length;
      final on = has && lineIdx == idx;
      rows.add(
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              has ? lines[lineIdx].text : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? p.lime : p.textTertiary,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        height: 84,
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.24, 0.76, 1],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Column(children: rows),
        ),
      ),
    );
  }

  Widget _queue(PlayerController c, Song song) {
    const p = fnDarkPalette;
    final queue = c.queue;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '播放队列',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: p.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '${queue.length} 首',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: FnText.monoFamily.first,
                  color: p.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < queue.length; i++)
            _queueRow(c, queue[i], i, queue[i].id == song.id),
        ],
      ),
    );
  }

  Widget _queueRow(PlayerController c, Song s, int index, bool on) {
    const p = fnDarkPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => c.playList(c.queue, index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: on ? p.limeSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            FnCover(songId: s.id, size: 34, radius: 7),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: on ? p.lime : p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    s.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              fmtDuration(s.duration),
              style: TextStyle(
                fontSize: 10,
                fontFamily: FnText.monoFamily.first,
                color: p.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

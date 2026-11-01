import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'fn_ui.dart';
import 'signal_path_sheet.dart';

/// laptop / desktop 档底部播放条（design/v3 `.pbar`）：72 高、三段式。
///
/// 左段封面 + 标题/艺术家，中段传输控制 + 进度，右段信号路径 / 音量 / 设备。
class PlayerBar extends StatefulWidget {
  const PlayerBar({
    super.key,
    this.drawerOpen = false,
    this.onOpenDrawer,
  });

  /// 右抽屉当前是否展开（用于按钮高亮）。
  final bool drawerOpen;

  /// 歌词按钮按 v3 shell.js 只负责打开抽屉（`toggleDrawer(true)`）。
  final VoidCallback? onOpenDrawer;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  Timer? _tick;
  Set<int> _favIds = <int>{};

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final favs = await ApiClient.instance.fetchFavorites();
      if (!mounted) return;
      setState(() {
        _favIds = favs.map((s) => s.id).toSet();
      });
    } catch (_) {}
  }

  Future<void> _toggleFav(Song song) async {
    final liked = _favIds.contains(song.id);
    setState(() {
      liked ? _favIds.remove(song.id) : _favIds.add(song.id);
    });
    try {
      if (liked) {
        await ApiClient.instance.removeFavorite(song.id);
      } else {
        await ApiClient.instance.addFavorite(song.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        liked ? _favIds.add(song.id) : _favIds.remove(song.id);
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    final song = c.current;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    // 无当前曲目时不占位（v3：播放条只在有播放内容时出现）。
    if (song == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final dense = w < 820;
        final compact = w < 1000;
        final leftW = dense ? 160.0 : (compact ? 240.0 : 280.0);
        final rightW = dense ? 214.0 : (compact ? 260.0 : 340.0);
        return Container(
          height: kFnBarH,
          decoration: BoxDecoration(
            color: FnColors.glass,
            border: Border(top: BorderSide(color: FnColors.line)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: leftW,
                child: _nowPlaying(context, c, song),
              ),
              Expanded(child: _transport(context, c, song, dense: compact)),
              SizedBox(
                width: rightW,
                child: _tools(context, c, zh, compact: compact || dense),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _nowPlaying(BuildContext context, PlayerController c, Song song) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // v3 shell.js：播放条封面 → player 全屏页（laptop/desktop 一致）；
      // 右侧抽屉只由面板按钮开启。收藏钮不触发跳转。
      onTap: () => context.push('/player'),
      child: Row(
        children: [
          FnCover(songId: song.id, size: 44, radius: 9),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FnColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: FnColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // design/v3 shell.js pbarMarkup：左段末尾 .pbar-fav 收藏钮。
          _iconButton(
            _favIds.contains(song.id)
                ? CupertinoIcons.heart_fill
                : CupertinoIcons.heart,
            size: 17,
            color: _favIds.contains(song.id)
                ? FnColors.coral
                : FnColors.textSecondary,
            onTap: () => _toggleFav(song),
          ),
        ],
      ),
    );
  }

  Widget _transport(BuildContext context, PlayerController c, Song song,
      {bool dense = false}) {
    final pos = c.positionSec;
    final dur = c.durationSec;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!dense)
              _iconButton(
                c.shuffle ? Icons.shuffle : Icons.shuffle,
                size: 17,
                color: c.shuffle ? FnColors.limeText : FnColors.textSecondary,
                onTap: () => setState(c.toggleShuffle),
              ),
            _iconButton(Icons.skip_previous_rounded, onTap: () => c.prev()),
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => c.togglePlay(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: FnColors.lime,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 21,
                  color: FnColors.limeInk,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _iconButton(Icons.skip_next_rounded, onTap: () => c.next()),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 22,
          child: FnScrubber(
            position: pos,
            duration: dur > 0 ? dur : (song.duration?.toDouble() ?? 0),
            height: 18,
            trackHeight: 3,
            onSeek: (v) => c.seek(v),
          ),
        ),
      ],
    );
  }

  Widget _tools(BuildContext context, PlayerController c, bool zh,
      {bool compact = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _iconButton(
          c.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          onTap: () => setState(c.toggleMute),
        ),
        if (!compact)
          SizedBox(
            width: 96,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: FnColors.lime,
                inactiveTrackColor: FnColors.textFaint,
                thumbColor: FnColors.textPrimary,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: c.muted ? 0 : c.volume,
                onChanged: (v) => setState(() => c.setVolume(v)),
              ),
            ),
          ),
        if (!compact)
          _iconButton(Icons.graphic_eq_rounded, onTap: () async {
            var presets = const <DspPreset>[];
            try {
              presets = await ApiClient.instance.fetchDspPresets();
            } catch (_) {}
            if (!context.mounted) return;
            await openSignalPath(context, presets: presets);
          }),
        _iconButton(Icons.speaker_rounded,
            onTap: () => context.push('/devices')),
        // design/v3 shell.js：`bar-lyrics` → `toggleDrawer(true)`，打开 NowPlaying 抽屉。
        _iconButton(Icons.lyrics_rounded,
            color: widget.drawerOpen ? FnColors.limeText : null,
            onTap: widget.onOpenDrawer),
        _iconButton(Icons.queue_music_rounded,
            onTap: () => context.push('/queue')),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _iconButton(IconData icon,
      {double size = 20, Color? color, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, size: size, color: color ?? FnColors.textSecondary),
      ),
    );
  }
}

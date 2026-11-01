import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../player_controller.dart';
import '../theme.dart';
import 'fn_ui.dart';

/// 悬浮迷你播放器：44 封面 + 标题/音质 + 2px 进度 + 下一首/播放。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
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
    if (song == null) return const SizedBox.shrink();
    final fmt = fnFormatOf(song);
    final dur = c.durationSec;
    final pos = c.positionSec;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/player'),
        child: Container(
          height: kFnMiniH,
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: FnColors.glass2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FnColors.line2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: FnColors.isDark ? 0.6 : 0.16),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              FnCover(songId: song.id, size: 44, radius: 11),
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
                      // 显式行高：56 高的迷你条只留 44 的内容区，若沿用主题
                      // （bodyMedium / 系统字体 1.4~1.5 倍行高）会憋出 2px 溢出。
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          fmt.label,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.28,
                            fontFamily: FnText.monoFamily.first,
                            color: fmt.color,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.2,
                              color: FnColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FnProgressBar(
                      value: dur > 0 ? pos / dur : 0,
                      height: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => PlayerController.instance.next(),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(CupertinoIcons.forward_end_fill,
                      size: 19, color: FnColors.textSecondary),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => PlayerController.instance.togglePlay(),
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
            ],
          ),
        ),
      ),
    );
  }
}

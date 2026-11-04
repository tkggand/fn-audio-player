import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 播放队列：当前曲目卡 + 接下来列表（长按排序 / 移除 / 清空）。
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  void _more(int index, Song song) {
    showFnSheet<void>(
      context,
      eyebrow: 'QUEUE',
      title: song.title,
      subtitle: song.artist,
      children: [
        FnOptionRow(
          title: '立即播放',
          icon: Icons.play_arrow_rounded,
          onTap: () {
            Navigator.pop(context);
            PlayerController.instance.playList(
              [...PlayerController.instance.queue],
              index,
            );
          },
        ),
        FnOptionRow(
          title: '上移一位',
          icon: Icons.arrow_upward_rounded,
          on: false,
          onTap: () {
            Navigator.pop(context);
            PlayerController.instance.moveQueue(index, index - 1);
          },
        ),
        FnOptionRow(
          title: '下移一位',
          icon: Icons.arrow_downward_rounded,
          onTap: () {
            Navigator.pop(context);
            PlayerController.instance.moveQueue(index, index + 1);
          },
        ),
        FnOptionRow(
          title: '从队列移除',
          icon: Icons.remove_circle_outline_rounded,
          danger: true,
          onTap: () {
            Navigator.pop(context);
            PlayerController.instance.removeQueueAt(index);
          },
        ),
      ],
    );
  }

  /// design/v3 js/pages/queue.js clearQueue：确认对话框「清空队列？」。
  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FnColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FnRadius.md),
          side: BorderSide(color: FnColors.line2),
        ),
        title: const Text('清空队列？', style: TextStyle(fontSize: 17)),
        content: Text(
          '将移除当前歌曲之后的所有待播曲目。',
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
    if (ok != true) return;
    PlayerController.instance.clearQueue();
    if (mounted) fnToast(context, '队列已清空');
  }

  /// design/v3 js/pages/queue.js `#q-more`：添加歌曲到队列 / 清空队列。
  void _moreSheet() {
    final c = PlayerController.instance;
    showFnSheet<void>(
      context,
      eyebrow: 'QUEUE',
      title: '播放队列',
      subtitle: '${c.queue.length} 首 · ${fmtDuration(c.queue.fold<double>(0, (a, s) => a + (s.duration ?? 0)))}',
      children: [
        FnOptionRow(
          title: '添加歌曲到队列',
          subtitle: '从曲库挑选',
          icon: Icons.add_rounded,
          onTap: () {
            Navigator.pop(context);
            context.go('/library?tab=songs');
          },
        ),
        FnOptionRow(
          title: '清空队列',
          icon: Icons.delete_outline_rounded,
          danger: true,
          onTap: () {
            Navigator.pop(context);
            _confirmClear();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PlayerController.instance;
    return StreamBuilder<void>(
      stream: c.stateChanges.stream,
      builder: (context, _) {
        final queue = c.queue;
        final cur = c.current;
        if (cur == null || queue.isEmpty) {
          return Scaffold(
            backgroundColor: FnColors.base,
            body: Column(
              children: [
                FnNav(
                  title: '播放队列',
                  subtitle: 'QUEUE',
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                const Expanded(
                  child: Center(
                    child: FnEmpty(
                      icon: CupertinoIcons.music_note_list,
                      title: '队列是空的',
                      message: '去听歌页选一首，或从曲库添加歌曲。',
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final upcoming = (queue.length - (c.index + 1)).clamp(0, queue.length);
        final bp = fnBpOf(context);
        final sub =
            '${c.isRoaming ? '漫游 · ' : ''}${queue.length} 首 · ${fmtDuration(queue.fold<double>(0, (a, s) => a + (s.duration ?? 0)))}';
        // design/v3 queue.js：eyebrow QUEUE + 「N 首 · 总时长」；宽档直接给「清空」，
        // mobile 的更多钮收进 sheet（添加歌曲 / 清空）。
        final head = bp.isWide
            ? FnPageHead(
                eyebrow: 'QUEUE',
                title: '播放队列',
                subtitle: sub,
                actions: [
                  FnButton(
                    label: '清空',
                    icon: Icons.delete_outline_rounded,
                    variant: FnButtonVariant.soft,
                    size: FnButtonSize.sm,
                    onTap: _confirmClear,
                  ),
                ],
              )
            : FnNav(
                title: '播放队列',
                subtitle: sub,
                onBack: () => Navigator.of(context).maybePop(),
                trailing: [
                  FnIconBtn(
                    icon: Icons.more_vert,
                    size: 34,
                    iconSize: 18,
                    variant: FnIconBtnVariant.plain,
                    onTap: _moreSheet,
                  ),
                ],
              );
        return Scaffold(
          backgroundColor: FnColors.base,
          body: Column(
            children: [
              head,
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ReorderableListView.builder(
                  padding: EdgeInsets.only(
                      top: 14, bottom: fnBottomGapOf(context)),
                  buildDefaultDragHandles: false,
                  itemCount: queue.length,
                  onReorder: (from, to) {
                    if (to > from) to--;
                    c.moveQueue(from, to);
                  },
                  header: Column(
                    children: [
                      _NowCard(song: cur),
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(kFnPad + 2, 12, kFnPad + 2, 0),
                        child: Text(
                          '正在播放来自：'
                          '${cur.album.trim().isEmpty ? '播放队列' : cur.album}',
                          style: TextStyle(
                            fontSize: 12,
                            color: FnColors.textSecondary,
                          ),
                        ),
                      ),
                      FnSectionHead(
                        title: '接下来',
                        sub: upcoming > 0
                            ? '$upcoming 首待播'
                            : '已是最后一首',
                        actionLabel: '随机',
                        onAction: () {
                          if (!c.shuffle) c.toggleShuffle();
                          fnToast(context, '随机播放已开启',
                              icon: Icons.shuffle_rounded);
                        },
                      ),
                    ],
                  ),
                  footer: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(kFnPad, 14, kFnPad, 0),
                        // design/v3 `.queue-add`：虚线描边 + lime 加号。
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => context.go('/library?tab=songs'),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: FnColors.line2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 16, color: FnColors.limeText),
                                const SizedBox(width: 6),
                                Text(
                                  '添加歌曲到队列',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: FnColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.drag_indicator_rounded,
                                size: 13, color: FnColors.textTertiary),
                            const SizedBox(width: 5),
                            Text(
                              '拖动排序 · 长按歌曲可上移、下移或移除',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  color: FnColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  itemBuilder: (context, i) {
                    final song = queue[i];
                    final isCurrent = i == c.index;
                    return Padding(
                      key: ValueKey('${song.id}-$i'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: kFnPad - 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCurrent ? FnColors.limeSoft : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: FnSongRow(
                                song: song,
                                ord: (i + 1).toString(),
                                isCurrent: isCurrent,
                                isPlaying: c.isPlaying,
                                onTap: () {
                                  c.playList(queue, i);
                                },
                                onMore: () => _more(i, song),
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: SizedBox(
                                width: 30,
                                height: 44,
                                child: Icon(Icons.drag_handle_rounded,
                                    size: 18,
                                    color: FnColors.textTertiary),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final bp = fnBpOf(context);
    final mobile = bp == FnBp.mobile;
    final fmt = fnFormatOf(song);
    final artSize = mobile ? 64.0 : 72.0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: kFnPad),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(mobile ? FnRadius.md : FnRadius.lg),
        border: Border.all(color: FnColors.line),
      ),
      child: Stack(
        children: [
          // design/v3 `.queue-now::before`：封面氛围光。
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
              child: Transform.scale(
                scale: 1.35,
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
          ),
          // design/v3 `.queue-now::after`：深色遮罩（浅色主题下换成浅遮罩）。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: FnColors.isDark
                      ? [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.66),
                        ]
                      : [
                          FnColors.surface.withValues(alpha: 0.78),
                          FnColors.surface.withValues(alpha: 0.86),
                        ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(mobile ? 14 : 16),
            child: Column(
              children: [
                Row(
                  children: [
                    FnCover(
                      songId: song.id,
                      size: artSize,
                      radius: mobile ? 10 : 12,
                    ),
                    SizedBox(width: mobile ? 12 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: FnColors.limeText,
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'NOW PLAYING',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.3,
                                  fontFamily: FnText.monoFamily.first,
                                  color: FnColors.limeText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: mobile ? 15 : 17,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${song.artist} · ${song.album} · ${fmt.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: mobile ? 10.5 : 11.5,
                                color: FnColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => PlayerController.instance.togglePlay(),
                      child: Container(
                        width: mobile ? 38 : 44,
                        height: mobile ? 38 : 44,
                        decoration: BoxDecoration(
                          color: FnColors.lime,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PlayerController.instance.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: mobile ? 19 : 21,
                          color: FnColors.limeInk,
                        ),
                      ),
                    ),
                  ],
                ),
                // design/v3 js/pages/queue.js `.qn-progress`：当前进度 + 总时长。
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FnScrubber(
                    position: PlayerController.instance.positionSec,
                    duration: PlayerController.instance.durationSec > 0
                        ? PlayerController.instance.durationSec
                        : (song.duration ?? 0),
                    buffered: PlayerController.instance.bufferedSec,
                    onSeek: PlayerController.instance.seek,
                    timeStyle: TextStyle(
                      fontSize: 10,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

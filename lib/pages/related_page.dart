import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/adaptive.dart';
import '../widgets/fn_ui.dart';

/// 相关推荐（v3 §4 B 组）：当前曲卡 + 相似歌曲网格
/// （mobile 单列横卡 / laptop 双列 / desktop 三列）。
class RelatedPage extends StatefulWidget {
  const RelatedPage({super.key, required this.songId});

  final int songId;

  @override
  State<RelatedPage> createState() => _RelatedPageState();
}

class _RelatedPageState extends State<RelatedPage> {
  bool _loading = true;
  String? _error;

  Song? _song;
  List<Song> _similar = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final song = PlayerController.instance.current?.id == widget.songId
          ? PlayerController.instance.current!
          : await ApiClient.instance.fetchSong(widget.songId);
      final similar = await ApiClient.instance.fetchRoamSongs(
          mode: 'similar', seedSongId: widget.songId, count: 9);
      if (!mounted) return;
      setState(() {
        _song = song;
        _similar = similar;
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

  void _refresh() {
    // 与 web 的 refreshSeed 同口径：重取相似列表，页面不闪回骨架。
    _load(quiet: true);
    fnToast(context, '已换一批推荐', icon: Icons.refresh_rounded);
  }

  void _playSimilar(int index) {
    if (_similar.isEmpty) return;
    PlayerController.instance.playList(_similar, index);
  }

  /// 相似度打分（与 v3 同口径）：基础 42，流派/艺人/同专辑/年代加权。
  int _scoreOf(Song s, Song? seed) {
    if (seed == null) return 50;
    var score = 42;
    if (s.genre != null && s.genre == seed.genre) score += 34;
    if (s.artist == seed.artist) score += 22;
    if (s.album.isNotEmpty && s.album == seed.album) score += 6;
    if (s.year != null &&
        seed.year != null &&
        (s.year! - seed.year!).abs() <= 2) {
      score += 4;
    }
    return score.clamp(42, 99);
  }

  String _whyOf(Song s, Song? seed) {
    if (seed == null) return '相似声音';
    final bits = <String>[];
    if (s.artist == seed.artist) bits.add('同艺人');
    if (s.genre != null && s.genre == seed.genre) bits.add('同为 ${s.genre}');
    if (s.year != null &&
        seed.year != null &&
        (s.year! - seed.year!).abs() <= 2) {
      bits.add('同期发行');
    }
    if (s.album.isNotEmpty && s.album == seed.album) bits.add('同专辑');
    return bits.isEmpty ? '相似声音' : bits.take(2).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final bp = fnBpOf(context);
    final wide = bp.isWide;
    final seed = _song;
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
                      title: '加载失败',
                      message: _error,
                      actionLabel: '重试',
                      onAction: _load,
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (wide)
                        FnPageHead(
                          eyebrow: 'RELATED',
                          title: '相关推荐',
                          subtitle: seed == null
                              ? '选择一首歌开始相似推荐'
                              : '与《${seed.title}》相似 · ${seed.artist}',
                          actions: [
                            FnIconBtn(
                              icon: Icons.refresh_rounded,
                              onTap: _refresh,
                            ),
                          ],
                        )
                      else
                        FnNav(
                          title: '相关推荐',
                          subtitle: seed == null
                              ? 'RELATED'
                              : '与《${seed.title}》相似',
                          trailing: [
                            FnIconBtn(
                              icon: Icons.refresh_rounded,
                              variant: FnIconBtnVariant.plain,
                              onTap: _refresh,
                            ),
                          ],
                        ),
                      _nowCard(seed),
                      FnSectionHead(
                        title: '相似歌曲',
                        sub: _similar.isEmpty
                            ? '—'
                            : '${_similar.length} 首 · 基于声学相似度',
                        actionLabel: '全部播放',
                        onAction: () => _playSimilar(0),
                      ),
                      _grid(bp, seed),
                    ],
                  ),
      ),
    );
  }

  /// 当前曲卡：封面 72 + NOW PLAYING + 曲名/艺人，右上角 --hue 氛围光。
  Widget _nowCard(Song? song) {
    final hue = song == null ? 120.0 : fnHue(song.id).toDouble();
    return Container(
      margin: const EdgeInsets.fromLTRB(kFnPad, 14, kFnPad, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FnColors.surface,
        borderRadius: BorderRadius.circular(FnRadius.lg),
        border: Border.all(color: FnColors.line2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.7, 0.52)
                .toColor()
                .withValues(alpha: 0.30),
            FnColors.surface.withValues(alpha: 0.0),
          ],
          stops: const [0, 0.64],
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              FnCover(songId: song?.id ?? 0, size: 72, radius: 12),
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0x80000000),
                    shape: BoxShape.circle,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in const [9.0, 6.0, 4.0])
                        Container(
                          width: 2,
                          height: h,
                          margin: const EdgeInsets.only(left: 1, bottom: 4),
                          decoration: BoxDecoration(
                            color: FnColors.lime,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOW PLAYING · 当前曲',
                    style: TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.limeText,
                    )),
                const SizedBox(height: 4),
                Text(song?.title ?? '未选择曲目',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    song == null
                        ? '从播放详情进入可看到完整信息'
                        : '${song.artist} · ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: FnColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(FnBp bp, Song? seed) {
    if (_similar.isEmpty) {
      return const FnEmpty(
        icon: CupertinoIcons.music_note,
        title: '暂时没有可推荐的曲目',
        message: '换一批或先播放更多歌曲。',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(kFnPad, 12, kFnPad, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (bp == FnBp.mobile) {
            return Column(
              children: [
                for (var i = 0; i < _similar.length; i++)
                  _mobileRow(_similar[i], seed, i),
              ],
            );
          }
          final cols = bp == FnBp.desktop ? 3 : 2;
          const gap = 16.0;
          final cell = (constraints.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: 20,
            children: [
              for (var i = 0; i < _similar.length; i++)
                SizedBox(
                  width: cell,
                  child: _gridCard(_similar[i], seed, i),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _gridCard(Song s, Song? seed, int index) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _playSimilar(index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: FnCover(
              songId: s.id,
              size: double.infinity,
              radius: 10,
            ),
          ),
          const SizedBox(height: 9),
          Text(s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('${s.artist} · ${fmtDuration(s.duration)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontSize: 11.5, color: FnColors.textTertiary)),
          _whyRow(s, seed),
        ],
      ),
    );
  }

  Widget _whyRow(Song s, Song? seed) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text('${_scoreOf(s, seed)}%',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                fontFamily: FnText.monoFamily.first,
                color: FnColors.limeText,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_whyOf(s, seed),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11, color: FnColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  /// mobile：横向行卡（封面 96 + 文案），避免整宽方形封面过高。
  Widget _mobileRow(Song s, Song? seed, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _playSimilar(index),
        child: Row(
          children: [
            FnCover(songId: s.id, size: 96, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('${s.artist} · ${fmtDuration(s.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: FnColors.textTertiary)),
                  _whyRow(s, seed),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

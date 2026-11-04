import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'fn_ui.dart';

/// 「我的」页顶部历史播放封面墙（design 参考：三列错位专辑瀑布墙）。
///
/// 左右两列缓慢向上、中间列反向向下，各列起始错位，形成「N 上 N+1 下」的交错感；
/// 列表首尾复制一次实现无缝循环。瓦片只显示封面，点击直接播放对应歌曲；
/// 正在播放的封面左下角显示跳动的均衡器。
class HistoryCoverWall extends StatefulWidget {
  const HistoryCoverWall({
    super.key,
    required this.songs,
    required this.onTap,
  });

  final List<Song> songs;
  final ValueChanged<Song> onTap;

  @override
  State<HistoryCoverWall> createState() => _HistoryCoverWallState();
}

class _HistoryCoverWallState extends State<HistoryCoverWall>
    with TickerProviderStateMixin {
  /// 封面墙可视高度（不含状态栏）。
  static const double _wallHeight = 360;

  /// 每列瓦片数：8 个 × 两列复制，保证循环时整列始终铺满。
  static const int _tilesPerColumn = 8;

  static const double _gap = 8;
  static const double _sidePad = 12;

  /// 一列内容走完一圈的时长：120s ≈ 8px/s，缓慢漂移。
  late final AnimationController _anim;

  /// 播放中均衡器的循环动画。
  late final AnimationController _bars;

  Timer? _stateTimer;
  int? _playingId;
  bool _playing = false;

  /// 是否已启用漂移：只有开始播放后才滚动，加载完成到点击之前保持静止。
  bool _motionStarted = false;

  @override
  void initState() {
    super.initState();
    // 初始静止：背景墙加载完成后不自行滚动，等用户点击播放再开始。
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    );
    _bars = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPlayState();
    _stateTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _syncPlayState(),
    );
  }

  /// 播放开始后启用漂移与均衡器循环；启用后持续运行。
  void _startMotion() {
    if (_motionStarted) return;
    _motionStarted = true;
    _anim.repeat();
    _bars.repeat();
  }

  /// 跟随播放器状态，只在「当前歌曲 / 播放状态」变化时重建。
  void _syncPlayState() {
    if (!mounted) return;
    final c = PlayerController.instance;
    final id = c.current?.id;
    final playing = c.isPlaying;
    if (playing) _startMotion();
    if (id == _playingId && playing == _playing) return;
    setState(() {
      _playingId = id;
      _playing = playing;
    });
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _anim.dispose();
    _bars.dispose();
    super.dispose();
  }

  /// 历史不足时循环复用，确保每列都有足够瓦片撑满可视区域。
  List<Song> _pooled() {
    final src = widget.songs;
    if (src.isEmpty) return const [];
    final out = <Song>[];
    while (out.length < _tilesPerColumn * 3) {
      out.addAll(src);
    }
    return out.take(_tilesPerColumn * 3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // 整块独立成层：逐帧位移只重绘本组件，不会把下方带模糊背景的头部一起重绘。
    return RepaintBoundary(
      child: SizedBox(
        height: top + 8 + _wallHeight,
        child: Padding(
          padding: EdgeInsets.only(top: top + 8),
          child: LayoutBuilder(
            builder: (context, box) {
              final colW = (box.maxWidth - _sidePad * 2 - _gap * 2) / 3;
              final pool = _pooled();
              final cols = [
                for (var c = 0; c < 3; c++)
                  [
                    for (var i = c; i < pool.length; i += 3) pool[i],
                  ],
              ];
              return Stack(
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: _sidePad),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var c = 0; c < 3; c++) ...[
                              if (c > 0) const SizedBox(width: _gap),
                              SizedBox(
                                width: colW,
                                child: _column(c, cols[c], colW, dpr),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 底部渐变蒙板：让封面墙缓缓融入下方资料头部，减小落差。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 170,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0, 0.55, 1],
                            colors: [
                              FnColors.base.withValues(alpha: 0),
                              FnColors.base.withValues(alpha: 0.45),
                              FnColors.base,
                            ],
                          ),
                        ),
                      ),
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

  Widget _column(int index, List<Song> songs, double colW, double dpr) {
    final content = _tiles(songs, colW, dpr);
    final copyHeight = content.$2;
    // 两侧向上、中间反向向下；右列额外半程错位，避免三列同步。
    final (double from, double to) = switch (index) {
      0 => (0, -1),
      1 => (-1, 0),
      _ => (-0.45, -1.45),
    };
    // 逐帧重绘本列（不走「平移合并图层」）：小数位移直接参与绘制采样，
    // 避免图层偏移被取整成整像素而在慢速漂移时出现台阶式顿感。
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        maxHeight: double.infinity,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            final y = (from + (to - from) * _anim.value) * copyHeight;
            // 命中测试必须跟随位移：否则点击命中的是「未位移」位置的瓦片，
            // 实际播放的就不是点中的那首歌。
            return Transform.translate(
              offset: Offset(0, y),
              child: child,
            );
          },
          child: Stack(
            children: [
              content.$1,
              ..._badges(songs, colW, copyHeight),
            ],
          ),
        ),
      ),
    );
  }

  /// 正在播放的封面中央叠加跳动均衡器。
  ///
  /// 与封面列共用一个位移变换、直接画在同一张显示列表里，
  /// 因此指示器跟随时不会另起图层造成位移取整或残影。
  List<Widget> _badges(List<Song> songs, double colW, double copyHeight) {
    final id = _playingId;
    if (!_playing || id == null) return const <Widget>[];
    final out = <Widget>[];
    var top = 0.0;
    for (var i = 0; i < songs.length; i++) {
      final h = colW * _ratio(i % 3);
      if (songs[i].id == id) {
        // 内容由两份瓦片拼成，两份都要画，滚动到任意一份都能看到。
        for (final t in <double>[top, top + copyHeight]) {
          out.add(
            Positioned(
              left: 0,
              width: colW,
              top: t + h / 2 - 16,
              height: 32,
              child: Center(child: _playingBadge()),
            ),
          );
        }
      }
      top += h + _gap;
    }
    return out;
  }

  /// 返回（一整列内容, 单份内容高度）；内容由两份相同瓦片拼成，循环时无断裂。
  (Widget, double) _tiles(List<Song> songs, double colW, double dpr) {
    final heights = <double>[];
    final tiles = <Widget>[];
    for (var i = 0; i < songs.length; i++) {
      final h = colW * _ratio(i % 3);
      heights.add(h);
      tiles.add(_tile(songs[i], colW, h, dpr));
      tiles.add(const SizedBox(height: _gap));
    }
    final copyHeight =
        heights.fold<double>(0, (s, v) => s + v) + _gap * songs.length;
    return (
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [...tiles, ...tiles],
      ),
      copyHeight,
    );
  }

  /// 瓦片高度比例，制造参考图的错落节奏。
  double _ratio(int i) => switch (i) {
        0 => 1.16,
        1 => 0.82,
        _ => 1.0,
      };

  Widget _tile(Song song, double w, double h, double dpr) {
    final px = (w * dpr).round();
    return SizedBox(
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(song),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            ApiClient.instance.coverUrl(song.id),
            fit: BoxFit.cover,
            cacheWidth: px,
            cacheHeight: (h * dpr).round(),
            errorBuilder: (_, __, ___) => DecoratedBox(
              decoration: BoxDecoration(gradient: fnCoverGradient(song.id)),
            ),
          ),
        ),
      ),
    );
  }

  /// 正在播放：封面中央的白色跳动均衡器（无底色、无投影，避免移动时出现拖影）。
  Widget _playingBadge() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _bars,
        builder: (context, _) {
          // 固定高度：柱子变长时只在底部对齐范围内伸缩，整组不会上下跳动。
          return SizedBox(
            height: 30,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Container(
                    width: 4,
                    height: 12 +
                        18 *
                            (0.5 +
                                0.5 *
                                    math.sin(
                                        _bars.value * 2 * math.pi + i * 2.1)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

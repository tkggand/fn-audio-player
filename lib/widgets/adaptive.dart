import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../theme.dart';
import 'fn_ui.dart';

/// 三档页面留白（design/v3 §5）：mobile 20 / laptop 24 / desktop 28。
double fnPadOf(BuildContext context) => fnPagePad(context);

/// 内容底部留白：mobile 让位 mini 条 + TabBar，宽屏由播放条承担（AppFrame）。
double fnBottomGapOf(BuildContext context) {
  if (!fnBpOf(context).isMobile) return 24;
  return fnDockHOf(GoRouterState.of(context).uri.path) + 12;
}

/// 三档网格列数（mobile 2 / laptop 3–4 / desktop auto-fill ≥4）。
int fnGridCols(
  BuildContext context, {
  int mobile = 2,
  int laptop = 3,
  int desktop = 6,
}) =>
    switch (fnBpOf(context)) {
      FnBp.mobile => mobile,
      FnBp.laptop => laptop,
      FnBp.desktop => desktop,
    };

/// 详情页封面边长：mobile 124 / laptop 150 / desktop 190。
double fnHeroCoverSize(BuildContext context) => switch (fnBpOf(context)) {
      FnBp.mobile => 124,
      FnBp.laptop => 150,
      FnBp.desktop => 190,
    };

/// 宽度受限的居中内容列（settings 760、登录卡等）。
class FnCenterBox extends StatelessWidget {
  const FnCenterBox({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 宽屏双列页（design/v3 §5）：左主区自适应、右辅区固定宽度；mobile 单列顺序拼接。
///
/// 头部（[head]）跨双列，左右两列各自独立滚动。
class FnSplitPage extends StatelessWidget {
  const FnSplitPage({
    super.key,
    required this.head,
    required this.left,
    required this.right,
    this.rightWidth = 420,
    this.pad = 24,
  });

  final Widget head;
  final List<Widget> left;
  final List<Widget> right;
  final double rightWidth;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final wide = fnBpOf(context).isWide;
    if (!wide) {
      return ListView(
        padding: EdgeInsets.only(bottom: fnBottomGapOf(context)),
        physics: const BouncingScrollPhysics(),
        children: [head, ...left, ...right],
      );
    }
    return Column(
      children: [
        head,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.only(bottom: pad),
                  physics: const BouncingScrollPhysics(),
                  children: left,
                ),
              ),
              SizedBox(
                width: fnBpOf(context) == FnBp.desktop ? rightWidth : rightWidth - 20,
                child: ListView(
                  padding: EdgeInsets.only(bottom: pad),
                  physics: const BouncingScrollPhysics(),
                  children: right,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 桌面档歌曲表格：排序表头 + hover 行 + 行尾操作。
///
/// 与 mobile/laptop 的 [FnSongRow] 行卡共用同一份数据（design/v3 §9 SongRow 双形态）。
class FnSongTable extends StatelessWidget {
  const FnSongTable({
    super.key,
    required this.songs,
    this.startIndex = 0,
    this.onPlay,
    this.onMore,
    this.onFavorite,
    this.favoriteIds = const <int>{},
    this.currentId,
    this.isPlaying = false,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.indexLabel = '#',
    this.ordinal,
    this.showArtist = true,
    this.showAlbum = true,
    this.showQuality = true,
    this.showFavorite = true,
    this.showHeader = true,
    this.selectionMode = false,
    this.selectedIds = const <int>{},
    this.onToggleSelect,
    this.onToggleAll,
  });

  final List<Song> songs;
  final int startIndex;

  /// 点击某行：参数为歌曲在 [songs] 中的下标。
  final void Function(int index)? onPlay;
  final void Function(int index)? onMore;
  final void Function(int index)? onFavorite;
  final Set<int> favoriteIds;
  final int? currentId;
  final bool isPlaying;

  /// 当前排序列：0 标题 / 1 艺人 / 2 专辑 / 3 时长。
  final int? sortColumn;
  final bool sortAscending;
  final void Function(int column)? onSort;

  final String indexLabel;

  /// 自定义序号文本（专辑页用 trackNo）；返回 null 时回退到顺序号。
  final String? Function(int index)? ordinal;
  final bool showArtist;
  final bool showAlbum;
  final bool showQuality;
  final bool showFavorite;
  final bool showHeader;

  /// 批量选择（歌单详情 desktop 批量编辑）。
  final bool selectionMode;
  final Set<int> selectedIds;
  final void Function(int index)? onToggleSelect;
  final VoidCallback? onToggleAll;

  @override
  Widget build(BuildContext context) {
    final pad = fnPadOf(context);
    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FnColors.line)),
              ),
              child: Row(
                children: [
                  if (selectionMode)
                    SizedBox(
                      width: 32,
                      child: _TableCheck(
                        value: songs.isNotEmpty &&
                            selectedIds.length == songs.length,
                        onTap: onToggleAll,
                      ),
                    ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      indexLabel,
                      style: _headStyle,
                    ),
                  ),
                  Expanded(
                    flex: 38,
                    child: _Th(
                      label: '标题',
                      active: sortColumn == 0,
                      asc: sortAscending,
                      onTap: onSort == null ? null : () => onSort!(0),
                    ),
                  ),
                  if (showArtist)
                    Expanded(
                      flex: 22,
                      child: _Th(
                        label: '艺人',
                        active: sortColumn == 1,
                        asc: sortAscending,
                        onTap: onSort == null ? null : () => onSort!(1),
                      ),
                    ),
                  if (showAlbum)
                    Expanded(
                      flex: 22,
                      child: _Th(
                        label: '专辑',
                        active: sortColumn == 2,
                        asc: sortAscending,
                        onTap: onSort == null ? null : () => onSort!(2),
                      ),
                    ),
                  if (showQuality) SizedBox(width: 96, child: Text('音质', style: _headStyle)),
                  SizedBox(
                    width: 64,
                    child: _Th(
                      label: '时长',
                      active: sortColumn == 3,
                      asc: sortAscending,
                      alignEnd: true,
                      onTap: onSort == null ? null : () => onSort!(3),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
            ),
          ),
        for (var i = 0; i < songs.length; i++)
          _SongTableRow(
            song: songs[i],
            ord: ordinal?.call(i) ?? (startIndex + i + 1).toString(),
            current: currentId == songs[i].id,
            playing: isPlaying && currentId == songs[i].id,
            fav: favoriteIds.contains(songs[i].id),
            showArtist: showArtist,
            showAlbum: showAlbum,
            showQuality: showQuality,
            showFavorite: showFavorite,
            onTap: onPlay == null ? null : () => onPlay!(i),
            onMore: onMore == null ? null : () => onMore!(i),
            onFavorite: onFavorite == null ? null : () => onFavorite!(i),
            selectionMode: selectionMode,
            selected: selectedIds.contains(songs[i].id),
            onToggleSelect:
                onToggleSelect == null ? null : () => onToggleSelect!(i),
            pad: pad,
          ),
      ],
    );
  }
}

TextStyle get _headStyle => TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: FnColors.textTertiary,
    );

/// 批量选择用的小方框（与 web 版 `.trow` 的勾选列同形）。
class _TableCheck extends StatelessWidget {
  const _TableCheck({required this.value, this.onTap});

  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: value ? FnColors.lime : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value ? FnColors.lime : FnColors.line2,
              width: 1.2,
            ),
          ),
          child: value
              ? Icon(Icons.check_rounded, size: 12, color: FnColors.limeInk)
              : null,
        ),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  const _Th({
    required this.label,
    this.active = false,
    this.asc = true,
    this.alignEnd = false,
    this.onTap,
  });

  final String label;
  final bool active;
  final bool asc;
  final bool alignEnd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Text(
          label,
          style: _headStyle.copyWith(
            color: active ? FnColors.limeText : FnColors.textTertiary,
          ),
        ),
        if (active) ...[
          const SizedBox(width: 3),
          Icon(
            asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 11,
            color: FnColors.limeText,
          ),
        ],
      ],
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: row,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: row,
      ),
    );
  }
}

class _SongTableRow extends StatefulWidget {
  const _SongTableRow({
    required this.song,
    required this.ord,
    required this.current,
    required this.playing,
    required this.fav,
    required this.showArtist,
    required this.showAlbum,
    required this.showQuality,
    required this.showFavorite,
    required this.pad,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.onTap,
    this.onMore,
    this.onFavorite,
  });

  final Song song;
  final String ord;
  final bool current;
  final bool playing;
  final bool fav;
  final bool showArtist;
  final bool showAlbum;
  final bool showQuality;
  final bool showFavorite;
  final double pad;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onTap;
  final VoidCallback? onMore;
  final VoidCallback? onFavorite;

  @override
  State<_SongTableRow> createState() => _SongTableRowState();
}

class _SongTableRowState extends State<_SongTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final titleColor = widget.current ? FnColors.lime : FnColors.textPrimary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.pad),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _hover
                  ? FnColors.glassLight
                  : widget.current
                      ? FnColors.limeSoft
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border(bottom: BorderSide(color: FnColors.line)),
            ),
            child: Row(
              children: [
                if (widget.selectionMode)
                  SizedBox(
                    width: 32,
                    child: _TableCheck(
                      value: widget.selected,
                      onTap: widget.onToggleSelect,
                    ),
                  ),
                SizedBox(
                  width: 34,
                  child: Text(
                    widget.playing ? '▶' : widget.ord,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: FnText.monoFamily.first,
                      color: widget.current
                          ? FnColors.limeText
                          : FnColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 38,
                  child: Row(
                    children: [
                      FnCover(songId: song.id, size: 34, radius: 6),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (widget.onMore != null)
                        _rowAction(
                          icon: Icons.more_horiz,
                          onTap: widget.onMore!,
                          visible: _hover,
                        ),
                    ],
                  ),
                ),
                if (widget.showArtist)
                  Expanded(
                    flex: 22,
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: FnColors.textSecondary,
                      ),
                    ),
                  ),
                if (widget.showAlbum)
                  Expanded(
                    flex: 22,
                    child: Text(
                      song.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: FnColors.textSecondary,
                      ),
                    ),
                  ),
                if (widget.showQuality)
                  SizedBox(
                    width: 96,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FnFmtBadge(song: song),
                    ),
                  ),
                SizedBox(
                  width: 64,
                  child: Text(
                    fmtDuration(song.duration),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: FnText.monoFamily.first,
                      color: FnColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.showFavorite && widget.onFavorite != null)
                        _rowAction(
                          icon: widget.fav
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          color: widget.fav
                              ? FnColors.coral
                              : FnColors.textTertiary,
                          onTap: widget.onFavorite!,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowAction({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    bool visible = true,
  }) {
    return Opacity(
      opacity: visible || widget.current ? 1 : 0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color ?? FnColors.textTertiary),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../breakpoints.dart';
import '../theme.dart';
import 'fn_ui.dart';
import 'mini_player.dart';

/// mobile 档应用外壳：底部 4 Tab（听歌 / 发现 / 曲库 / 我的）+ 迷你播放器 + 底部导航。
///
/// 迷你播放器只在发现 / 曲库页展示，与底部导航同为毛玻璃材质叠在内容之上；
/// Tab 页内容按 [fnDockHOf] 预留底部空间。
/// laptop / desktop 档由 [AppFrame] 提供 Rail/Sidebar + 播放条，这里直接透传。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  /// 由路由推导当前 Tab（design/v3.js/shell.js tabbarMarkup：仅页面 key 精确匹配）。
  int get _index {
    return switch (location) {
      '/' || '/listen' => 0,
      '/discover' => 1,
      '/library' => 2,
      '/me' => 3,
      _ => -1,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!fnBpOf(context).isMobile) return child;
    // mini 条只在发现 / 曲库页展示：听歌页本身是全屏播放器，我的页不需要。
    final showMini = fnMiniOnRoute(location);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    // 统一 Material outlined 图标，并按字形实际墨迹尺寸补偿字号：
    // 实测 24pt 下墨迹高度 explore/library ≈ 20、
    // person_outline 仅 ≈ 16，所以「我的」放大到 29 才能与其余图标视觉等大。
    final items = <_TabItem>[
      _TabItem(zh ? '听歌' : 'Listen', Icons.headphones_outlined, size: 24),
      _TabItem(zh ? '发现' : 'Discover', Icons.explore_outlined, size: 24),
      _TabItem(zh ? '曲库' : 'Library', Icons.library_music_outlined,
          size: 24),
      _TabItem(zh ? '我的' : 'Me', Icons.person_outline, size: 29),
    ];

    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: FnColors.base,
      body: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showMini) const MiniPlayer(),
                _TabBar(
                  currentIndex: _index,
                  items: items,
                  onTap: (i) => context.go(
                    switch (i) {
                      0 => '/',
                      1 => '/discover',
                      2 => '/library',
                      _ => '/me',
                    },
                  ),
                  safeBottom: bottom,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
    required this.safeBottom,
  });

  final int currentIndex;
  final List<_TabItem> items;
  final ValueChanged<int> onTap;
  final double safeBottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: 7, bottom: safeBottom),
      decoration: BoxDecoration(
        color: FnColors.glass,
        border: Border(top: BorderSide(color: FnColors.line)),
      ),
      child: SizedBox(
        height: kFnTabH - 7,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              _tab(context, i, i == currentIndex),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int index, bool on) {
    final item = items[index];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: SizedBox(
        width: 76,
        child: Semantics(
          button: true,
          label: item.label,
          selected: on,
          child: Icon(
            item.icon,
            size: item.size,
            color: on ? FnColors.limeText : FnColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;

  /// 图标字号：按字形墨迹尺寸补偿，使各 Tab 视觉大小一致。
  final double size;
  const _TabItem(this.label, this.icon, {this.size = 24});
}

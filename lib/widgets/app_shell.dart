import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'fn_ui.dart';
import 'mini_player.dart';

/// mobile 档应用外壳：4 Tab（听歌 / 发现 / 曲库 / 我的）+ 悬浮迷你播放器 + 底部导航。
///
/// 迷你播放器与底部导航同为毛玻璃材质，叠在页面内容之上；
/// Tab 页内容需要预留 [kFnDockInset] 的底部空间。
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
    // listen 页本身是全屏播放器，不再叠 mini 条；底部 4 Tab 保留，否则进听歌后无法切换。
    final isListen = location == '/' || location == '/listen';
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final items = <_TabItem>[
      _TabItem(zh ? '听歌' : 'Listen', CupertinoIcons.waveform),
      _TabItem(zh ? '发现' : 'Discover', CupertinoIcons.compass),
      _TabItem(zh ? '曲库' : 'Library', CupertinoIcons.collections),
      _TabItem(zh ? '我的' : 'Me', CupertinoIcons.person),
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
                if (!isListen && PlayerController.instance.current != null)
                  const MiniPlayer(),
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
        // 选中点与 CSS `.tab::after` 同形：绝对定位在顶部留白里，不占内容高度。
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  size: 23,
                  color: on ? FnColors.limeText : FnColors.textTertiary,
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.2,
                    color: on ? FnColors.textPrimary : FnColors.textTertiary,
                  ),
                ),
              ],
            ),
            Positioned(
              top: -7,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: on ? 1 : 0,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: FnColors.lime,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem(this.label, this.icon);
}

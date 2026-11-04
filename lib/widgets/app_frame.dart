import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'app_shell.dart';
import 'now_playing_drawer.dart';
import 'player_bar.dart';

/// laptop / desktop 档的外壳：Rail 72（laptop）或 Sidebar 232/72（desktop）+ 底部播放条 72。
///
/// mobile 档直接透传子页面（沿用 TabBar + 悬浮 mini 条，由 [AppShell] 提供）；
/// player / lyrics 是全屏沉浸页，三档都不套壳（design/v3 §5）。
class AppFrame extends StatefulWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  State<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends State<AppFrame> {
  bool _collapsed = false;
  bool _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    final bp = fnBpOf(context);
    final loc = GoRouterState.of(context).uri.path;
    // 壳例外（design/v3 §4/§5）：player / lyrics 三档全屏沉浸；
    // listen 在 mobile / laptop 是全屏封面流，desktop 并入首页（discover）；
    // login 独立页不加载壳（js/shell.js inject 的 page === 'login' 判断）。
    if (loc == '/login' || loc == '/player' ||
        (bp == FnBp.laptop && (loc == '/' || loc == '/listen'))) {
      return widget.child;
    }

    // mobile：除 login / player 外的页面都挂 4 Tab；mini 条只在发现 / 曲库页展示。
    if (bp.isMobile) {
      return AppShell(location: loc, child: widget.child);
    }

    if (bp == FnBp.desktop && (loc == '/' || loc == '/listen')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/discover');
      });
      return widget.child;
    }

    // laptop / desktop 的「我的」并入设置页。
    if (loc == '/me') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/settings');
      });
      return widget.child;
    }

    final side = bp == FnBp.laptop
        ? const _Rail()
        : _Sidebar(
            collapsed: _collapsed,
            onToggle: () => setState(() => _collapsed = !_collapsed),
          );
    // v3：NowPlaying 右抽屉在 laptop / desktop 均可用（宽度 380）。
    final drawerOpen = _drawerOpen;

    return Scaffold(
      backgroundColor: FnColors.base,
      body: Stack(
        children: [
          Row(
            children: [
              side,
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: widget.child),
                    PlayerBar(
                      drawerOpen: drawerOpen,
                      onOpenDrawer: () => setState(() => _drawerOpen = true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 抽屉展开时，右侧以外的区域点按即收起（底边让开播放条 72）。
          if (_drawerOpen)
            Positioned(
              top: 0,
              left: 0,
              right: kFnDrawerW,
              bottom: kFnBarH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _drawerOpen = false),
              ),
            ),
          // NowPlaying 右抽屉：380 宽，底边让开播放条（design/v3 §8）。
          Positioned(
            top: 0,
            right: 0,
            bottom: kFnBarH,
            child: NowPlayingDrawer(
              open: _drawerOpen,
              onClose: () => setState(() => _drawerOpen = false),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String zh;
  final String en;
  final String path;
  final IconData icon;
  const _NavItem(this.zh, this.en, this.path, this.icon);
}

const List<_NavItem> _mainNav = [
  _NavItem('首页', 'Home', '/discover', Icons.home_rounded),
  _NavItem('曲库', 'Library', '/library', Icons.library_music_rounded),
  _NavItem('搜索', 'Search', '/search', Icons.search_rounded),
  _NavItem('歌单', 'Playlists', '/playlists', Icons.queue_music_rounded),
];

const List<_NavItem> _libNav = [
  _NavItem('专辑', 'Albums', '/library?tab=albums', Icons.album_rounded),
  _NavItem('艺人', 'Artists', '/library?tab=artists', Icons.mic_rounded),
  _NavItem('流派', 'Genres', '/library?tab=genres', Icons.auto_awesome_rounded),
  _NavItem('播放历史', 'History', '/history', Icons.history_rounded),
];

const List<_NavItem> _sysNav = [
  _NavItem('调音', 'Tuning', '/tuning', Icons.tune_rounded),
  _NavItem('响度均衡', 'ReplayGain', '/replaygain', Icons.speed_rounded),
  _NavItem('播放设备', 'Devices', '/devices', Icons.speaker_rounded),
  _NavItem('扫描曲库', 'Scan', '/scan', Icons.sync_rounded),
  _NavItem('设置', 'Settings', '/settings', Icons.settings_rounded),
];

String _label(BuildContext context, _NavItem item) =>
    Localizations.localeOf(context).languageCode == 'zh' ? item.zh : item.en;

bool _isActive(Uri uri, _NavItem item) {
  final loc = uri.path;
  if (item.path == '/discover') return loc == '/discover' || loc == '/home';
  if (item.path == '/library') {
    return loc == '/library' ||
        loc.startsWith('/album/') ||
        loc.startsWith('/artist/') ||
        loc.startsWith('/genre/') ||
        loc == '/songs';
  }
  if (item.path.startsWith('/library?tab=')) {
    final tab = item.path.split('?tab=').last;
    return loc == '/library' && uri.queryParameters['tab'] == tab;
  }
  if (item.path == '/playlists') {
    return loc == '/playlists' || loc.startsWith('/playlist/');
  }
  return loc == item.path;
}

/// laptop 档：72px 图标栏（Logo + 主导航 + 底部用户入口）。
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kFnRailW,
      decoration: BoxDecoration(
        color: FnColors.base2,
        border: Border(right: BorderSide(color: FnColors.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          const _LogoMark(size: 30),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in _mainNav)
                  _railItem(context, item,
                      _isActive(GoRouterState.of(context).uri, item)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/settings'),
              child: const _UserAvatar(size: 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railItem(BuildContext context, _NavItem item, bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Tooltip(
        message: _label(context, item),
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go(item.path),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: on ? FnColors.limeSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              size: 20,
              color: on ? FnColors.limeText : FnColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// desktop 档：232px 分组侧栏，可折叠到 72。
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    // design/v3 shell.js `.user-card`：真实用户名 + 当前音质标签。
    final name = ApiClient.instance.username ?? 'FN';
    final tag = switch (PlayerController.instance.quality) {
      'cd' => 'CD',
      'hd' => 'HD',
      'high' => '256',
      'standard' => '128',
      _ => 'FLAC',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? kFnSideWC : kFnSideW,
      decoration: BoxDecoration(
        color: FnColors.base2,
        border: Border(right: BorderSide(color: FnColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(collapsed ? 18 : 16, 18, 10, 14),
            child: Row(
              children: [
                const _LogoMark(size: 30),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FN Audio',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: FnColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Hi-Res · DSD · EQ',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 0.3,
                            fontFamily: FnText.monoFamily.first,
                            color: FnColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!collapsed)
                  _IconSquare(
                    icon: Icons.keyboard_double_arrow_left_rounded,
                    onTap: onToggle,
                  ),
              ],
            ),
          ),
          if (collapsed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: _IconSquare(
                  icon: Icons.keyboard_double_arrow_right_rounded,
                  onTap: onToggle,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final item in _mainNav)
                  _sideItem(context, item, _isActive(uri, item)),
                _group(zh ? '资料库' : 'Library'),
                for (final item in _libNav)
                  _sideItem(context, item, _isActive(uri, item)),
                _group(zh ? '系统' : 'System'),
                for (final item in _sysNav)
                  _sideItem(context, item, _isActive(uri, item)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/settings'),
              child: Container(
                height: 52,
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                decoration: BoxDecoration(
                  color: FnColors.glassLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    const _UserAvatar(size: 32),
                    if (!collapsed) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: FnColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: FnColors.limeSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  fontFamily: FnText.monoFamily.first,
                                  color: FnColors.limeText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String label) {
    if (collapsed) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: FnColors.textTertiary,
        ),
      ),
    );
  }

  Widget _sideItem(BuildContext context, _NavItem item, bool on) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: collapsed ? _label(context, item) : '',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go(item.path),
          child: Container(
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: on ? FnColors.limeSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  size: 19,
                  color: on ? FnColors.limeText : FnColors.textSecondary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _label(context, item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                        color: on ? FnColors.limeText : FnColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: FnColors.lime,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Text(
        'FN',
        style: TextStyle(
          fontSize: size * 0.43,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: FnColors.limeInk,
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FnColors.surface3, FnColors.surface2],
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.52,
        color: FnColors.textSecondary,
      ),
    );
  }
}

class _IconSquare extends StatelessWidget {
  const _IconSquare({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(icon, size: 18, color: FnColors.textTertiary),
      ),
    );
  }
}

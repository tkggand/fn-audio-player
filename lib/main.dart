// ignore_for_file: prefer_const_constructors
// 本文件的 widget 读取运行时主题令牌（FnColors），const 实例化会冻结配色导致切换主题不刷新，见 lib/theme.dart。
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'background_audio.dart';
import 'l10n/l10n.dart';
import 'pages/album_page.dart';
import 'pages/artist_page.dart';
import 'pages/devices_page.dart';
import 'pages/discover_page.dart';
import 'pages/genre_page.dart';
import 'pages/history_page.dart';
import 'pages/library_page.dart';
import 'pages/listen_page.dart';
import 'pages/login_page.dart';
import 'pages/me_page.dart';
import 'pages/player_page.dart';
import 'pages/playlists_page.dart';
import 'pages/queue_page.dart';
import 'pages/related_page.dart';
import 'pages/replaygain_page.dart';
import 'pages/scan_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/songs_page.dart';
import 'pages/tuning_page.dart';
import 'player_controller.dart';
import 'sync_client.dart';
import 'system_media.dart';
import 'theme.dart';
import 'widgets/app_frame.dart';

bool _playerInitDone = false;

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      await ApiClient.instance.loadSession();
      final loggedIn = ApiClient.instance.token != null;
      if (loggedIn && !_playerInitDone) {
        _playerInitDone = true;
        PlayerController.instance.init();
        // Windows 系统媒体控件（任务栏显示与播放控制）。
        SystemMediaService.instance.init();
      } else if (loggedIn) {
        // 重登或切换服务器后，确保 WS 同步链路重新建立（内部已防重复建链）。
        SyncClient.instance.connect();
      }
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      // 宽屏外壳：laptop 走 Rail、desktop 走 Sidebar，并挂底部播放条；
      // mobile 档 [AppFrame] 直接透传子页面（TabBar + mini 条由 AppShell 提供）。
      ShellRoute(
        builder: (context, state, child) => AppFrame(child: child),
        routes: [
          // 常驻底部 4 Tab + 迷你播放器：由 [AppFrame] 在 mobile 档统一注入，
          // 分支仅负责保持各 Tab 的导航栈（design/v3 js/shell.js）。
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/', builder: (context, state) => const ListenPage()),
                // design/v3 §4：mobile/laptop 的沉浸听歌页路由别名 /listen。
                GoRoute(
                    path: '/listen',
                    builder: (context, state) => const ListenPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/discover',
                    builder: (context, state) => const DiscoverPage()),
                // design/v3 §4：desktop 档首页路由别名 home（同一 discover 页面）。
                GoRoute(
                    path: '/home',
                    builder: (context, state) => const DiscoverPage()),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/library',
                    builder: (context, state) => LibraryPage(
                          initialTab:
                              state.uri.queryParameters['tab'] ?? 'songs',
                        )),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/me', builder: (context, state) => const MePage()),
              ]),
            ],
          ),
          // 子页面（覆盖底部 Tab，全屏展示）。
          GoRoute(
              path: '/playlists',
              builder: (context, state) => const PlaylistsPage()),
          GoRoute(
            path: '/playlist/:id',
            builder: (context, state) => PlaylistDetailPage(
              playlistId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
              path: '/songs', builder: (context, state) => const SongsPage()),
          GoRoute(
              path: '/tuning', builder: (context, state) => const TuningPage()),
          // 播放详情：从迷你播放器点击进入，缩放过渡表现为「放大到全屏」。
          GoRoute(
            path: '/player',
            pageBuilder: (context, state) => CustomTransitionPage<void>(
              key: state.pageKey,
              child: const PlayerPage(),
              transitionDuration: const Duration(milliseconds: 320),
              reverseTransitionDuration: const Duration(milliseconds: 260),
              transitionsBuilder: (context, animation, secondary, child) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
                    child: child,
                  ),
                );
              },
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/related/:id',
            builder: (context, state) => RelatedPage(
              songId: int.parse(state.pathParameters['id'] ?? '0'),
            ),
          ),
          GoRoute(
            path: '/album/:id',
            builder: (context, state) => AlbumPage(
              albumId: int.parse(state.pathParameters['id'] ?? '0'),
              title: state.uri.queryParameters['title'],
              artist: state.uri.queryParameters['artist'],
              coverSongId:
                  int.tryParse(state.uri.queryParameters['cover'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/artist/:name',
            builder: (context, state) =>
                ArtistPage(name: state.pathParameters['name'] ?? ''),
          ),
          GoRoute(
            path: '/genre/:name',
            builder: (context, state) =>
                GenrePage(name: state.pathParameters['name'] ?? ''),
          ),
          GoRoute(
              path: '/queue', builder: (context, state) => const QueuePage()),
          GoRoute(
              path: '/history',
              builder: (context, state) => const HistoryPage()),
          GoRoute(
              path: '/replaygain',
              builder: (context, state) => const ReplayGainPage()),
          GoRoute(
              path: '/devices',
              builder: (context, state) => const DevicesPage()),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage()),
        ],
      ),
    ],
  );
});

void main() async {
  // SharedPreferences 需要在 runApp 前读主题/语言选择，先初始化绑定。
  WidgetsFlutterBinding.ensureInitialized();
  // Android/iOS：初始化系统后台播放服务（通知、锁屏、控制中心）；桌面为空操作。
  await BackgroundAudio.instance.init();
  FnThemeController.instance.load();
  FnLocaleController.instance.load();
  runApp(const ProviderScope(child: FnAudioApp()));
}

class FnAudioApp extends ConsumerStatefulWidget {
  const FnAudioApp({super.key});

  @override
  ConsumerState<FnAudioApp> createState() => _FnAudioAppState();
}

class _FnAudioAppState extends ConsumerState<FnAudioApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 「跟随系统」时，系统切换深浅色需要重算令牌并重绘当前路由。
    if (FnThemeController.instance.value == FnThemeMode.auto) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // 主题 / 语言任一变化都重建 MaterialApp。
    return AnimatedBuilder(
      animation: Listenable.merge([
        FnThemeController.instance,
        FnLocaleController.instance,
      ]),
      builder: (context, _) {
        final ScrollBehavior? behavior = (Platform.isIOS || Platform.isAndroid)
            ? null
            : const MaterialScrollBehavior().copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.trackpad,
                },
              );
        final mode = FnThemeController.instance.value;
        final localeMode = FnLocaleController.instance.value;
        // 静态令牌需先写入亮度，让尚未迁移到 Theme.of(context) 的页面取到新配色。
        FnColors.applyBrightness(mode.brightness);
        // 路由栈里的页面不构成 InheritedWidget 依赖，只重建 MaterialApp 会残留旧配色，
        // 首帧后 refresh 一次让当前路由按新令牌重绘，同时保留导航状态。
        WidgetsBinding.instance.addPostFrameCallback((_) => router.refresh());
        return MaterialApp.router(
          title: 'FN Audio',
          debugShowCheckedModeBanner: false,
          theme: FnThemes.light,
          darkTheme: FnThemes.dark,
          scrollBehavior: behavior,
          themeMode: switch (mode) {
            FnThemeMode.dark => ThemeMode.dark,
            FnThemeMode.light => ThemeMode.light,
            FnThemeMode.auto => ThemeMode.system,
          },
          locale: localeMode.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        );
      },
    );
  }
}

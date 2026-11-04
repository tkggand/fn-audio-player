import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../breakpoints.dart';
import '../discovery.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fn_ui.dart';

/// 登录页属于「始终深色区域」（design/v3 §8），固定使用深色调色板，
/// 不随应用浅色主题切换。
const FnPalette _p = fnDarkPalette;

/// 登录：封面拼贴背景 + 品牌头 + 大标题 + 服务器/账号/密码表单。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {
  static const _rememberKey = 'fn_login_remember';
  static const _userKey = 'fn_login_username';
  /// 与设置页「自动发现服务器」开关共用同一键。
  static const _autoDiscoverKey = 'fn_auto_discover';

  /// 输入框圆角：比列表/卡片小一档，避免与卡片视觉同级。
  static const _fieldRadius = BorderRadius.all(Radius.circular(10));

  final _baseUrl = TextEditingController(text: ApiClient.instance.baseUrl);
  final _username = TextEditingController();
  final _password = TextEditingController();

  late final AnimationController _shake;
  /// 扫描局域网时让「发现」图标轻微呼吸，替代转圈 spinner。
  late final AnimationController _pulse;
  late final Animation<double> _pulseFade;
  bool _loading = false;
  bool _pwdVisible = false;
  bool _remember = true;
  bool _discovering = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseFade = Tween<double>(begin: 0.3, end: 1).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _restore();
  }

  @override
  void dispose() {
    _shake.dispose();
    _pulse.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final autoDiscover = prefs.getBool(_autoDiscoverKey) ?? true;
    setState(() {
      _remember = prefs.getBool(_rememberKey) ?? true;
      final saved = prefs.getString(_userKey);
      if (saved != null && saved.isNotEmpty) {
        _username.text = saved;
      } else {
        _username.text = 'admin';
      }
    });
    // 开启「自动发现服务器」且没有手动填写过地址时，进入登录页静默扫一次局域网。
    if (autoDiscover && !ApiClient.instance.hasCustomBase) {
      unawaited(_autoDiscover());
    }
  }

  void _fail(String message) {
    setState(() {
      _error = message;
      _status = null;
    });
    _shake.forward(from: 0);
  }

  Future<void> _login() async {
    final l = context.l10n;
    final server = _baseUrl.text.trim();
    final user = _username.text.trim();
    final pass = _password.text;
    if (server.isEmpty) return _fail('请填写服务器地址');
    if (user.isEmpty) return _fail('请填写账号');
    if (pass.isEmpty) return _fail('请填写密码');

    setState(() {
      _loading = true;
      _error = null;
      _status = '正在握手 · $server';
    });
    try {
      final input = server;
      if (input != ApiClient.instance.baseUrl) {
        await ApiClient.instance.setBaseUrl(input);
      }
      await ApiClient.instance.login(user, pass);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _remember);
      if (_remember) {
        await prefs.setString(_userKey, user);
      } else {
        await prefs.remove(_userKey);
      }
      if (!mounted) return;
      setState(() => _status = '已同步曲库 · 正在进入');
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = null;
      });
      _fail(e is FormatException
          ? l.serverInvalid(serverUrlErrorText(l, e.message))
          : l.loginFailed('$e'));
    }
  }

  /// 扫描局域网 mDNS 并返回第一个 HTTP 探测可达的服务端。
  Future<DiscoveredServer?> _findReachable() async {
    // 同机后端优先探测：Windows 上多个进程共享 5353 端口时，只有最后绑定的
    // socket 能收到组播，后端收不到 App 发出的查询，同机 mDNS 必然失败。
    final DiscoveredServer? local = _localServer();
    if (local != null && await ServerDiscovery.probe(local.baseUrl)) {
      return local;
    }
    final List<DiscoveredServer> servers = await ServerDiscovery.find();
    for (final DiscoveredServer server in servers) {
      if (await ServerDiscovery.probe(server.baseUrl)) return server;
    }
    return null;
  }

  /// 由平台默认地址构造「本机服务器」候选（桌面版通常直接连本机后端）。
  DiscoveredServer? _localServer() {
    final Uri? uri = Uri.tryParse(ApiClient.platformDefault);
    if (uri == null || uri.host.isEmpty) return null;
    return DiscoveredServer(
      name: '本机服务器',
      host: uri.host,
      port: uri.hasPort ? uri.port : 80,
    );
  }

  /// 统一控制扫描态：驱动发现图标的呼吸动画，避免出现突兀的转圈 spinner。
  void _setDiscovering(bool value) {
    setState(() => _discovering = value);
    if (value) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  /// 静默自动发现：找到就填入地址，找不到保留当前默认值，不打扰用户。
  Future<void> _autoDiscover() async {
    if (_discovering) return;
    _setDiscovering(true);
    final DiscoveredServer? target = await _findReachable();
    if (!mounted) return;
    _setDiscovering(false);
    if (target != null) _baseUrl.text = target.baseUrl;
  }

  /// 手动「发现」：扫描局域网并给出明确反馈。
  Future<void> _discover() async {
    if (_discovering) return;
    _setDiscovering(true);
    setState(() {
      _error = null;
      _status = '正在扫描局域网…';
    });
    final DiscoveredServer? target = await _findReachable();
    if (!mounted) return;
    _setDiscovering(false);
    setState(() => _status = null);

    if (target == null) {
      final current = _baseUrl.text.trim();
      final fallback = ApiClient.platformDefault;
      if (current.isEmpty) {
        _baseUrl.text = fallback;
        fnToast(context, '未发现服务器，已填入默认地址 $fallback',
            icon: Icons.wifi_tethering_rounded);
      } else {
        fnToast(context, '未发现服务器，请确认与本机处于同一局域网',
            icon: Icons.wifi_tethering_rounded);
      }
      return;
    }
    _baseUrl.text = target.baseUrl;
    fnToast(context, '已发现 ${target.name} · ${target.baseUrl}',
        icon: Icons.wifi_tethering_rounded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _p.base,
      body: Stack(
        children: [
          const _LoginBackdrop(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  kFnPad, 18, kFnPad, fnBpOf(context).isWide ? 40 : 24),
              physics: const BouncingScrollPhysics(),
              child: Align(
                alignment: fnBpOf(context).isWide
                    ? Alignment.center
                    : Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: fnBpOf(context).isWide ? 460 : 760),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _brand(),
                  const SizedBox(height: 34),
                  Text('SELF-HOSTED · 自托管曲库',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.5,
                        fontFamily: FnText.monoFamily.first,
                        color: _p.lime,
                      )),
                  const SizedBox(height: 9),
                  Text('把整个曲库\n装进口袋。',
                      style: TextStyle(
                        fontSize: 36,
                        height: 1.14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.9,
                        color: _p.textPrimary,
                      )),
                  const SizedBox(height: 11),
                  Text(
                    '无损、专辑、播放列表，从你的 NAS 直达耳机。没有广告，没有云端，只有音乐。',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.65,
                        color: _p.textSecondary),
                  ),
                  const SizedBox(height: 28),
                  _field(
                    label: '服务器地址',
                    icon: CupertinoIcons.desktopcomputer,
                    controller: _baseUrl,
                    hint: 'IP:端口 或 域名',
                    keyboardType: TextInputType.url,
                    trailing: GestureDetector(
                      onTap: _discovering ? null : _discover,
                      child: Tooltip(
                        message: _discovering ? '正在扫描局域网…' : '自动发现服务器',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          // 扫描中让图标轻微呼吸，位置和大小保持不变。
                          child: FadeTransition(
                            opacity: _discovering
                                ? _pulseFade
                                : const AlwaysStoppedAnimation<double>(1),
                            child: Icon(Icons.wifi_tethering_rounded,
                                size: 18, color: _p.lime),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: '账号',
                    icon: CupertinoIcons.person,
                    controller: _username,
                    hint: '用户名',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    label: '密码',
                    icon: CupertinoIcons.lock,
                    controller: _password,
                    hint: '密码',
                    obscure: !_pwdVisible,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    trailing: GestureDetector(
                      onTap: () => setState(() => _pwdVisible = !_pwdVisible),
                      child: Tooltip(
                        message: _pwdVisible ? '隐藏密码' : '显示密码',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          child: Icon(
                              _pwdVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18,
                              color: _p.lime),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _remember = !_remember),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: _remember
                                    ? _p.lime
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                    color: _remember
                                        ? _p.lime
                                        : _p.line2),
                              ),
                              child: _remember
                                  ? Icon(Icons.check_rounded,
                                      size: 11, color: _p.limeInk)
                                  : null,
                            ),
                            const SizedBox(width: 7),
                            Text('记住此设备',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: _p.textSecondary)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => fnToast(
                            context, '服务器地址由管理员在网页端维护',
                            icon: Icons.tune_rounded),
                        child: Text('服务器设置',
                            style: TextStyle(
                                fontSize: 11.5, color: _p.textTertiary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      final t = _shake.value;
                      final dx = t == 0
                          ? 0.0
                          : (8 *
                              (1 - t) *
                              (t < 0.5 ? 1 : -1) *
                              (0.6 + 0.4 * (1 - t)));
                      return Transform.translate(
                          offset: Offset(dx, 0), child: child);
                    },
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        style: FilledButton.styleFrom(
                          backgroundColor: _p.lime,
                          foregroundColor: _p.limeInk,
                          disabledBackgroundColor:
                              _p.lime.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: _loading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CupertinoActivityIndicator(
                                      color: _p.limeInk, radius: 8),
                                  const SizedBox(width: 9),
                                  Text('正在连接',
                                      style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: _p.limeInk
                                              .withValues(alpha: 0.7))),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('进入曲库',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  Icon(CupertinoIcons.chevron_forward,
                                      size: 15, color: _p.limeInk),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: _p.coral))
                  else if (_status != null)
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: _p.lime, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_status!,
                              style: TextStyle(
                                  fontSize: 11, color: _p.textTertiary)),
                        ),
                      ],
                    )
                  else
                    Text('局域网直连 · 凭据仅保存在本机',
                        style: TextStyle(
                            fontSize: 11, color: _p.textFaint)),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Text('FN AUDIO 2.0',
                          style: TextStyle(
                              fontSize: 9.5,
                              letterSpacing: 1,
                              fontFamily: FnText.monoFamily.first,
                              color: _p.textFaint)),
                      const Spacer(),
                      Text('局域网直连',
                          style: TextStyle(
                              fontSize: 9.5, color: _p.textFaint)),
                    ],
                  ),
                ],
              ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _brand() {
    return Row(
      children: [
        const FnBrandMark(size: 40),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FN AUDIO',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: _p.textPrimary)),
            Text('PRIVATE MUSIC LIBRARY',
                style: TextStyle(
                    fontSize: 7.5,
                    letterSpacing: 1.3,
                    fontFamily: FnText.monoFamily.first,
                    color: _p.textTertiary)),
          ],
        ),
      ],
    );
  }

  Widget _field({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                  color: _p.textTertiary)),
        ),
        SizedBox(
          height: 46,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 14, color: _p.textPrimary),
            cursorColor: _p.lime,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: _p.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              // 图标嵌在输入框内：左侧固定占位，右侧留给发现/显示按钮。
              prefixIcon: Icon(icon, size: 17, color: _p.textTertiary),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 44),
              suffixIcon: trailing,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 44),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 14, color: _p.textFaint),
              border: const OutlineInputBorder(
                borderRadius: _fieldRadius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: _fieldRadius,
                borderSide: BorderSide(color: _p.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: _fieldRadius,
                borderSide: BorderSide(color: _p.lime, width: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 背景：四块倾斜的「封面」拼贴 + 深色遮罩。
class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            ColoredBox(color: _p.base),
            Positioned(
              left: -76,
              top: -60,
              child: _tile(188, 20, 0.62, const [Color(0xFF2C4B3A), Color(0xFF0B1410)]),
            ),
            Positioned(
              right: -64,
              top: 34,
              child: _tile(168, -16, 0.5, const [Color(0xFF3A2C4B), Color(0xFF120B16)]),
            ),
            Positioned(
              left: 30,
              top: 250,
              child: _tile(150, 12, 0.42, const [Color(0xFF4B3A22), Color(0xFF171008)]),
            ),
            Positioned(
              right: 6,
              top: 330,
              child: _tile(132, -8, 0.36, const [Color(0xFF22384B), Color(0xFF080F17)]),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _p.base.withValues(alpha: 0.30),
                    _p.base.withValues(alpha: 0.72),
                    _p.base,
                  ],
                  stops: const [0, 0.5, 0.92],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(double size, double angle, double opacity, List<Color> colors) {
    return Transform.rotate(
      angle: angle * 3.14159 / 180,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
      ),
    );
  }
}

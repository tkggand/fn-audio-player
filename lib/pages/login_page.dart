import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../breakpoints.dart';
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
    with SingleTickerProviderStateMixin {
  static const _rememberKey = 'fn_login_remember';
  static const _userKey = 'fn_login_username';

  final _baseUrl = TextEditingController(text: ApiClient.instance.baseUrl);
  final _username = TextEditingController();
  final _password = TextEditingController();

  late final AnimationController _shake;
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
    _restore();
  }

  @override
  void dispose() {
    _shake.dispose();
    _baseUrl.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _remember = prefs.getBool(_rememberKey) ?? true;
      final saved = prefs.getString(_userKey);
      if (saved != null && saved.isNotEmpty) {
        _username.text = saved;
      } else {
        _username.text = 'admin';
      }
    });
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

  Future<void> _discover() async {
    if (_discovering) return;
    setState(() => _discovering = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    final current = _baseUrl.text.trim();
    final fallback = ApiClient.platformDefault;
    setState(() => _discovering = false);
    if (current.isEmpty) {
      _baseUrl.text = fallback;
      fnToast(context, '已填入默认地址 $fallback',
          icon: Icons.wifi_tethering_rounded);
    } else {
      fnToast(context, '未发现其他服务器，请确认地址',
          icon: Icons.wifi_tethering_rounded);
    }
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
                      child: _discovering
                          ? const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.6),
                            )
                          : Text('自动发现',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _p.lime)),
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
                      child: Text(_pwdVisible ? '隐藏' : '显示',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _p.lime)),
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
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: _p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _p.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: _p.textTertiary),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  autocorrect: false,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  style: TextStyle(fontSize: 14, color: _p.textPrimary),
                  cursorColor: _p.lime,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                        fontSize: 14, color: _p.textFaint),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
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

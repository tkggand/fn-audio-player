import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

/// WebSocket 多端同步客户端（Design §3.7）。
///
/// 登录后 [connect]，自动 5 秒重连；[messages] 广播同用户其他设备的事件。
/// 服务端只转发白名单类型（play_state / lyric / dsp_preset / queue / ping），
/// 且不回发发送方。
class SyncClient {
  SyncClient._();
  static final SyncClient instance = SyncClient._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _closedByUser = false;
  bool get connected => _channel != null;

  void connect() {
    if (ApiClient.instance.token == null) return;
    // 已存在连接时不重复建链（重连由 onDone/onError 调度）。
    if (_channel != null) return;
    _closedByUser = false;
    final channel = WebSocketChannel.connect(Uri.parse(ApiClient.instance.syncWsUrl()));
    _channel = channel;
    channel.stream.listen(
      (data) {
        if (data is String) {
          try {
            final json = jsonDecode(data);
            if (json is Map<String, dynamic>) _controller.add(json);
          } catch (_) {
            // 忽略非 JSON 帧
          }
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void disconnect() {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void send(Map<String, dynamic> msg) {
    final channel = _channel;
    if (channel != null) channel.sink.add(jsonEncode(msg));
  }

  void _scheduleReconnect() {
    _channel = null;
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }
}

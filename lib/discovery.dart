import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// 局域网内通过 mDNS 发现的服务端。
class DiscoveredServer {
  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
  });

  /// 服务实例名（不含 `.local` 后缀），例如 `FN-Audio (NAS)`。
  final String name;

  /// 解析出的 A/AAAA 记录中的 IP。
  final String host;
  final int port;

  String get baseUrl => 'http://$host:$port';
}

/// `_fnaudio._tcp` mDNS 发现：后端启动时通过 `mdns-sd` 广播同一服务类型，
/// App 登录页据此自动填充服务器地址。
///
/// iOS 走系统 Bonjour（`NSNetServiceBrowser`，见 ios/Runner/AppDelegate.swift）：
/// iOS 14+ 对裸 socket 的组播收发要求 Multicast Networking 权限（需 Apple 审批），
/// `multicast_dns` 的原始组播包会被系统丢弃；Bonjour 由系统 mDNSResponder 代理，
/// 只需 `NSBonjourServices` 声明即可。其它平台仍用 `multicast_dns`。
class ServerDiscovery {
  ServerDiscovery._();

  /// 与后端 `mdns::SERVICE_TYPE` 保持一致（仅忽略末尾的点）。
  static const String serviceType = '_fnaudio._tcp.local';

  static const MethodChannel _channel = MethodChannel('fn_audio/discovery');

  /// 扫描局域网内的 FN Audio 服务端。
  ///
  /// 返回去重后的服务列表；环境不支持组播（端口被占用、无网卡等）时返回空，
  /// 由调用方回退到手动填写地址。
  static Future<List<DiscoveredServer>> find({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (Platform.isIOS) {
      final List<DiscoveredServer> viaBonjour = await _findViaBonjour(timeout);
      if (viaBonjour.isNotEmpty) return viaBonjour;
    }
    return _findViaMdns(timeout);
  }

  /// iOS：调用原生 Bonjour 通道，失败或超时返回空。
  static Future<List<DiscoveredServer>> _findViaBonjour(
      Duration timeout) async {
    try {
      final List<dynamic>? raw = await _channel.invokeListMethod<dynamic>(
        'discover',
        // 原生侧浏览窗口要覆盖单实例解析（resolve 有 3s 超时），否则会提前收尾。
        <String, Object>{'timeoutMs': timeout.inMilliseconds + 1500},
      );
      if (raw == null) return const <DiscoveredServer>[];
      final List<DiscoveredServer> out = <DiscoveredServer>[];
      for (final dynamic item in raw) {
        if (item is! Map) continue;
        final dynamic name = item['name'];
        final dynamic host = item['host'];
        final dynamic port = item['port'];
        if (name is! String || host is! String || port is! int) continue;
        final DiscoveredServer server =
            DiscoveredServer(name: name, host: host, port: port);
        if (out.any((s) => s.baseUrl == server.baseUrl)) continue;
        out.add(server);
      }
      return out;
    } catch (_) {
      return const <DiscoveredServer>[];
    }
  }

  static Future<List<DiscoveredServer>> _findViaMdns(
      Duration timeout) async {
    final MDnsClient client = MDnsClient();
    final List<DiscoveredServer> found = <DiscoveredServer>[];
    try {
      await client.start();
      await for (final PtrResourceRecord ptr
          in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
        timeout: timeout,
      )) {
        final SrvResourceRecord? srv = await _first(
          client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 2),
          ),
        );
        if (srv == null) continue;

        // IPv4 优先；纯 IPv6 局域网再退回 AAAA。
        final IPAddressResourceRecord? ip = await _first(
              client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target),
                timeout: const Duration(seconds: 1),
              ),
            ) ??
            await _first(
              client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv6(srv.target),
                timeout: const Duration(seconds: 1),
              ),
            );
        if (ip == null) continue;

        final DiscoveredServer server = DiscoveredServer(
          name: ptr.domainName.split('.').first,
          host: ip.address.address,
          port: srv.port,
        );
        if (found.any((s) => s.baseUrl == server.baseUrl)) continue;
        found.add(server);
      }
    } catch (_) {
      // 组播端口被占用 / 权限被拒等：交由调用方走手动填写兜底。
    } finally {
      try {
        client.stop();
      } catch (_) {
        // start 中途失败时 stop 会抛 StateError，忽略即可（socket 由 GC 回收）。
      }
    }
    return found;
  }

  /// 探测服务端是否真的可用：mDNS 只能证明同名服务存在，可能被同名程序冒领，
  /// 也可能服务端 HTTP 未就绪。
  static Future<bool> probe(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final HttpClient http = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest req =
          await http.getUrl(Uri.parse('$baseUrl/api/health'));
      final HttpClientResponse res = await req.close();
      await res.drain<void>();
      return res.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      http.close(force: true);
    }
  }

  /// 取流的首个元素；无结果（超时）时返回 null，不抛异常。
  static Future<T?> _first<T>(Stream<T> stream) async {
    try {
      return await stream.first;
    } catch (_) {
      return null;
    }
  }
}

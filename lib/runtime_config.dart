import 'api.dart';

/// 运行时行为开关缓存：`/api/system/config` 下发的三个播放行为开关，
/// 供播放器 / 多端同步在运行时实时读取（无需重启）。
///
/// - [softMute]：暂停瞬间做约 20ms 增益斜坡淡出（默认 true）。
/// - [autoPlayNext]：曲终自动接播放队列下一首（默认 true）。
/// - [syncEnabled]：多端播放状态同步上报 / 跟随（默认 true）。
class RuntimeConfig {
  RuntimeConfig._();
  static final RuntimeConfig instance = RuntimeConfig._();

  bool softMute = true;
  bool autoPlayNext = true;
  bool syncEnabled = true;

  /// 启动拉取一次并写入；失败保持默认值，不弹错误。
  Future<void> load() async {
    try {
      apply(await ApiClient.instance.getSystemConfig());
    } catch (_) {
      // 拉取失败：保持默认值 true/true/true
    }
  }

  /// 用服务端配置回填（设置页保存成功后调用，即时生效）。
  void apply(SystemConfig c) {
    softMute = c.softMute;
    autoPlayNext = c.autoPlayNext;
    syncEnabled = c.syncEnabled;
  }
}

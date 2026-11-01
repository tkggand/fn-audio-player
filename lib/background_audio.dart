import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'api.dart';
import 'player_controller.dart';

/// 移动端后台播放与系统媒体控制：Android 通知栏 / 锁屏 / 耳机线，
/// iOS 锁屏与「控制中心」的播放、暂停、上一首、下一首、拖动进度。
///
/// 用原生 [AudioService] 而不是 `just_audio_background`：后者的上一首/下一首
/// 只对 ConcatenatingAudioSource 生效，而本 App 的队列由 [PlayerController]
/// 自己维护（逐首换源，音质/预设/ReplayGain 都会改变拉流 URL）。
///
/// 桌面（Windows）不走这里：SMTC 由 system_media.dart 负责。
class BackgroundAudio {
  BackgroundAudio._();
  static final BackgroundAudio instance = BackgroundAudio._();

  FnAudioHandler? _handler;

  /// Windows / Linux / macOS 为 false，不做任何事。
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 在 `main()` 中调用一次（早于创建 AudioPlayer）。
  Future<void> init() async {
    if (!isSupported || _handler != null) return;
    try {
      _handler = await AudioService.init(
        builder: () => FnAudioHandler(PlayerController.instance),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.fnaudio.fn_audio.channel.audio',
          androidNotificationChannelName: 'FN Audio 播放',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('[audio] 系统媒体控制初始化失败: $e');
    }
  }
}

/// 把 [PlayerController] 的状态映射成系统媒体控制（通知/锁屏/控制中心）。
class FnAudioHandler extends BaseAudioHandler with SeekHandler {
  FnAudioHandler(this._c) {
    // 播放器状态每次变化（含 500ms 心跳）都刷新一次，保证系统侧进度不落后。
    _sub = _c.stateChanges.stream.listen((_) => _publish());
    _publish();
  }

  final PlayerController _c;
  StreamSubscription<void>? _sub;
  int? _lastSongId;

  void _publish() {
    final song = _c.current;
    if (song != null && song.id != _lastSongId) {
      _lastSongId = song.id;
      mediaItem.add(MediaItem(
        id: '${song.id}',
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: Duration(seconds: (song.duration ?? 0).round()),
        artUri: Uri.tryParse(ApiClient.instance.coverUrl(song.id)),
      ));
    }
    final posMs = (_c.positionSec * 1000).round();
    final bufMs = (_c.bufferedSec * 1000).round();
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        _c.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState:
          song == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: _c.isPlaying,
      updatePosition: Duration(milliseconds: posMs),
      bufferedPosition: Duration(milliseconds: bufMs),
      speed: 1.0,
    ));
  }

  @override
  Future<void> play() => _c.resume();

  @override
  Future<void> pause() => _c.pause();

  @override
  Future<void> seek(Duration position) =>
      _c.seek(position.inMilliseconds / 1000.0);

  @override
  Future<void> skipToNext() => _c.next();

  @override
  Future<void> skipToPrevious() => _c.prev();

  @override
  Future<void> stop() async {
    await _c.pause();
    await super.stop();
  }

  /// 退出通知/监听（App 生命周期内用不到，保留以便未来注销账号时清理）。
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import 'api.dart';
import 'player_controller.dart';

/// 系统媒体传输控件（SMTC）集成：在 Windows 任务栏 / 系统媒体浮层显示当前曲目
/// 与播放进度，并响应系统的 播放/暂停、上一首、下一首。
///
/// 仅在 Windows 生效（`smtc_windows` 只实现了 Windows）；其他平台不做任何事，
/// 后续接入移动端时可在此按平台扩展。
class SystemMediaService {
  SystemMediaService._();
  static final SystemMediaService instance = SystemMediaService._();

  SMTCWindows? _smtc;
  StreamSubscription? _stateSub;
  StreamSubscription? _buttonSub;
  int? _lastSongId;
  bool? _lastPlaying;

  /// 登录后调用一次：初始化 SMTC 并接管播放状态。
  Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      await SMTCWindows.initialize();
      _smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: false,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
      );

      final controller = PlayerController.instance;
      _buttonSub = _smtc!.buttonPressStream.listen((btn) {
        switch (btn) {
          case PressedButton.play:
          case PressedButton.pause:
            controller.togglePlay();
          case PressedButton.next:
            controller.next();
          case PressedButton.previous:
            controller.prev();
          default:
            break;
        }
      });
      _stateSub = controller.stateChanges.stream.listen((_) => _sync());
      _sync();
    } catch (e) {
      // 初始化失败不影响播放功能。
      debugPrint('SMTC 初始化失败: $e');
    }
  }

  /// 将当前播放状态同步到系统媒体控件（曲目信息仅在切歌时更新）。
  void _sync() {
    final smtc = _smtc;
    if (smtc == null) return;
    final controller = PlayerController.instance;
    final song = controller.current;

    if (song == null) {
      if (_lastSongId != null) {
        _lastSongId = null;
        _lastPlaying = null;
        smtc.clearMetadata();
        smtc.setPlaybackStatus(PlaybackStatus.stopped);
      }
      return;
    }

    if (_lastSongId != song.id) {
      _lastSongId = song.id;
      smtc.updateMetadata(MusicMetadata(
        title: song.title,
        artist: song.artist,
        album: song.album,
        albumArtist: song.artist,
        thumbnail: ApiClient.instance.coverUrl(song.id),
      ));
    }

    final playing = controller.isPlaying;
    if (_lastPlaying != playing) {
      _lastPlaying = playing;
      smtc.setPlaybackStatus(
          playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    }

    final endMs = (controller.durationSec * 1000).round();
    smtc.updateTimeline(PlaybackTimeline(
      startTimeMs: 0,
      endTimeMs: endMs,
      positionMs: (controller.positionSec * 1000).round(),
      minSeekTimeMs: 0,
      maxSeekTimeMs: endMs,
    ));
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _buttonSub?.cancel();
    _smtc?.dispose();
    _smtc = null;
  }
}

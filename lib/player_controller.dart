import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, debugPrint, kIsWeb;
import 'package:fn_audio_engine/fn_audio_engine.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'play_log.dart';
import 'runtime_config.dart';
import 'sync_client.dart';

/// 循环模式：关 / 列表循环 / 单曲循环。
enum LoopMode { off, all, one }

/// 全局播放器单例：跨页面共享播放状态、播放队列、多端同步、音量、DLNA 投屏。
class PlayerController {
  PlayerController._();
  static final PlayerController instance = PlayerController._();

  /// 诊断开关：`--dart-define=FN_DEBUG_RATE=true` 时周期性打印
  /// 播放速率与位置推进，用于排查"语速过快"。
  static const bool _debugRate = bool.fromEnvironment('FN_DEBUG_RATE');

  final AudioPlayer player = AudioPlayer();
  Song? current;
  final List<Song> _queue = [];
  int _index = -1;
  List<Song> get queue => List.unmodifiable(_queue);
  int get index => _index;

  int? _presetId;
  String _quality = 'lossless';
  String _rgMode = 'off'; // ReplayGain：off / track / album
  bool _suppressUntil = false; // 收到远端跟随动作期间抑制回声
  DateTime _suppressUntilTime = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本端刚发起播放动作后的短暂窗口：期间忽略远端 play_state，
  /// 避免另一端（仍停留在上一首）的回声把用户刚点的歌顶掉。
  DateTime _localActionUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// 加载请求编号：并发加载时只保留最新一次的结果，旧请求自动作废。
  int _loadToken = 0;

  // ---------------- 本地引擎（Rust 全格式解码 + 本地 DSP） ----------------

  /// 用户开关（设置页手动开启，默认关）。
  static const _localEngineKey = 'fn_audio_local_engine';
  bool _localEngine = false;
  /// Rust 侧输出设备已就绪（初始化一次后复用）。
  bool _engineReady = false;
  /// 当前曲目是否由本地引擎承载（false 时一律走 just_audio）。
  bool _usingEngine = false;
  /// 本地引擎失败过的曲目：本曲不再重试，直接回退系统播放器，避免来回抖动。
  int? _engineFailedSongId;
  /// 正在进行的引擎初始化：并发点播共用同一次，避免重复加载动态库。
  Future<bool>? _engineInitTask;
  /// 引擎初始化已失败：不再每次点播都重试（重新打开开关会重置）。
  bool _engineInitFailed = false;
  /// 最近一次状态快照（进度 / 时长 / 缓冲 / 是否在播）。
  EngineStatus? _engineStatus;
  /// 是否已派发过"本曲结束"，避免 500ms 轮询重复触发切歌。
  bool _engineEndedHandled = false;
  /// 本地引擎 seek 的乐观目标：解码线程真正追上前先用它显示进度，
  /// 否则拖动结束后滑条会被 500ms 的状态轮询拉回旧位置（表现为"拖不动"）。
  double? _engineSeekTarget;
  DateTime _engineSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get localEngineEnabled => _localEngine;
  bool get usingLocalEngine => _usingEngine;

  /// 本地引擎只在这三个平台可用（cpal + libopus 均已适配）。
  bool get _engineSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 最近一次播放失败原因（首页 / 详情页据此给出反馈，而不是静默失败）。
  String? _lastError;
  String? get lastError => _lastError;
  void clearLastError() => _lastError = null;

  // 音量
  double _volume = 1.0;
  bool _muted = false;
  double get volume => _volume;
  bool get muted => _muted;

  // 随机 / 循环
  bool _shuffle = false;
  LoopMode _repeat = LoopMode.off;
  bool get shuffle => _shuffle;
  LoopMode get repeat => _repeat;

  // 漫游：非空表示当前队列由漫游生成，播到队尾时自动续批。
  String? _roamMode;
  int? _roamSeedId;
  final Set<int> _roamSeen = <int>{};
  bool get isRoaming => _roamMode != null;
  String? get roamMode => _roamMode;

  // DLNA 投屏
  DlnaRenderer? _dlnaRenderer;
  DlnaStatus? _dlnaStatus;
  Timer? _dlnaPoll;
  String? _lastTransport;
  DlnaRenderer? get dlnaRenderer => _dlnaRenderer;
  DlnaStatus? get dlnaStatus => _dlnaStatus;
  bool get isCasting => _dlnaRenderer != null;

  /// 状态变化通知（页面刷新用）。
  final StreamController<void> stateChanges =
      StreamController<void>.broadcast();

  /// 初始化（登录后调用一次）：读取持久化音效/音质/音量、建立 WS 与状态监听。
  Future<void> init() async {
    if (Platform.isIOS) await _configureIosAudioSession();
    final prefs = await SharedPreferences.getInstance();
    _presetId = prefs.getInt('fn_audio_preset');
    _quality = prefs.getString('fn_audio_quality') ?? 'lossless';
    _rgMode = prefs.getString('fn_audio_rg_mode') ?? 'off';
    _volume = (prefs.getDouble('fn_audio_volume') ?? 1.0).clamp(0.0, 1.0);
    _muted = prefs.getBool('fn_audio_muted') ?? false;
    await player.setVolume(_effectiveVolume());

    // 本地引擎开关（默认关）：开启后后台初始化输出设备，失败自动留在 just_audio。
    _localEngine = prefs.getBool(_localEngineKey) ?? false;
    // iOS 推迟到首次播放再建输出流：引擎建流会激活 AVAudioSession，
    // 启动时就激活会打断用户正在播放的其他 App 音乐。
    if (_localEngine && !Platform.isIOS) unawaited(_initLocalEngine());

    // 启动拉取一次运行时开关（失败保持默认 true/true/true）。
    await RuntimeConfig.instance.load();

    SyncClient.instance.connect();

    // 播放 / 暂停 广播
    player.playerStateStream.listen((st) {
      _broadcastState(st.playing);
    });

    // 播放错误（解码失败 / 格式不支持 / 网络中断）必须显式接住：
    // 否则 await 之外的异步异常会被静默丢弃，表现为"点了没反应"。
    player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) {
        _lastError = _describeError(e);
        stateChanges.add(null);
      },
    );

    // 每 500ms 广播一次（mini bar 进度 + DLNA 状态）
    final t0 = DateTime.now();
    Timer.periodic(const Duration(milliseconds: 500), (_) {
      _tickEngine();
      if (current != null) {
        stateChanges.add(null);
        if (_debugRate) {
          final el = DateTime.now().difference(t0).inMilliseconds;
          debugPrint('[rate] wall=${el}ms speed=${player.speed} '
              'pos=${player.position.inMilliseconds}ms '
              'dur=${player.duration?.inMilliseconds} '
              'state=${player.processingState} playing=${player.playing}');
        }
      }
    });

    // 播放结束自动下一首
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) handleEnded();
    });

    // 多端同步：接收其他设备的播放状态
    SyncClient.instance.messages.listen((msg) async {
      switch (msg['type']) {
        case 'play_state':
          // 多端同步关闭：忽略远端播放状态，不改变本地播放。
          if (!RuntimeConfig.instance.syncEnabled) break;
          await _onRemotePlayState(msg);
          break;
        case 'dsp_preset':
          final pid = msg['preset_id'];
          final newPreset = pid is int ? pid : null;
          if (newPreset != _presetId) {
            _presetId = newPreset;
            await _persistPreset(newPreset);
            if (current != null && !isCasting) {
              await _loadCurrent();
            }
          }
          break;
      }
    });

    // 启动后校验本地持久化预设 id 是否仍存在（系统预设升级/删除后旧 id 失效），
    // 失效则清空回退直通，避免误判服务端处理流、带无效 preset_id、RG 分支错乱。
    _validatePresetOnStartup();
  }

  /// iOS：把会话类别配成 music（静音键下仍出声、支持锁屏/切后台，配合
  /// Info.plist 的 UIBackgroundModes），并接管「耳机拔出」事件。
  ///
  /// 会话的激活不在这里做：本地引擎由 Rust 侧在建流/起播时激活（见
  /// `fn_audio_engine` 的 `engine/ios.rs`），避免启动就抢占其他 App 的音频。
  Future<void> _configureIosAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // 本地引擎不经过 just_audio，插拔耳机这类系统事件需要自己处理：
      // 拔出耳机后继续外放会突然变大声，与系统音乐 App 一致，直接暂停。
      session.becomingNoisyEventStream.listen((_) {
        if (isPlaying) unawaited(pause());
      });
    } catch (e) {
      debugPrint('[audio] 音频会话配置失败: $e');
    }
  }

  Future<void> _onRemotePlayState(Map<String, dynamic> msg) async {
    final songId = msg['song_id'] as int?;
    if (songId == null) return;
    // 本端刚点播不久：忽略远端状态，避免把用户刚点的歌顶掉。
    if (DateTime.now().isBefore(_localActionUntil)) return;
    final playing = msg['playing'] as bool? ?? false;
    final position = (msg['position'] as num?)?.toDouble() ?? 0;

    if (current == null || current!.id != songId) {
      try {
        final song = await ApiClient.instance.fetchSong(songId);
        _queue
          ..clear()
          ..add(song);
        _index = 0;
        current = song;
        stateChanges.add(null);
        // 跟随远端曲目时不自动起播：是否播放由远端的 playing 决定。
        await _loadCurrent(autoplay: false);
      } catch (_) {
        return;
      }
    }
    _suppressUntilTime = DateTime.now().add(const Duration(milliseconds: 1500));
    _suppressUntil = true;
    if (isCasting) {
      stateChanges.add(null);
      return;
    }
    final currentPos = positionSec;
    if ((currentPos - position).abs() > 3) {
      if (_usingEngine) {
        engineSeek(secs: position);
      } else {
        await player.seek(Duration(milliseconds: (position * 1000).round()));
      }
    }
    if (playing && !isPlaying) {
      if (_usingEngine) {
        enginePlay();
      } else {
        _playIgnoringErrors();
      }
    } else if (!playing && isPlaying) {
      await _pausePlayer();
    }
    stateChanges.add(null);
  }

  Future<void> _persistPreset(int? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('fn_audio_preset');
    } else {
      await prefs.setInt('fn_audio_preset', id);
    }
  }

  /// 以后端最新预设列表校准当前选中 id：本地缓存的预设已不存在时清空并持久化，
  /// 已在播则切回直通流。返回是否发生了变更。
  Future<bool> reconcilePreset(List<DspPreset> presets) async {
    final pid = _presetId;
    if (pid == null) return false;
    if (presets.any((p) => p.id == pid)) return false;
    _presetId = null;
    await _persistPreset(null);
    if (current != null && !isCasting) await _loadCurrent();
    stateChanges.add(null);
    return true;
  }

  /// 启动后拉取预设列表并校准；后端暂不可达时保留本地选择，不阻断启动。
  Future<void> _validatePresetOnStartup() async {
    if (_presetId == null) return;
    try {
      final presets = await ApiClient.instance.fetchDspPresets();
      await reconcilePreset(presets);
    } catch (_) {
      // 网络/接口失败：保持现状，待下次拉取预设时再兜底。
    }
  }

  // ---------------- 本地引擎 ----------------

  /// 初始化本地引擎（加载动态库 + 建输出流）。失败时静默留在 just_audio。
  ///
  /// 并发点播共用同一次初始化，避免重复加载动态库。
  Future<bool> _initLocalEngine() {
    final task = _engineInitTask;
    if (task != null) return task;
    _engineInitTask = _doInitLocalEngine().whenComplete(() {
      _engineInitTask = null;
    });
    return _engineInitTask!;
  }

  Future<bool> _doInitLocalEngine() async {
    if (!_engineSupported) {
      _engineReady = false;
      return false;
    }
    try {
      await RustLib.init();
      _engineReady = await engineInit(timeoutMs: BigInt.from(3000));
    } catch (e) {
      debugPrint('[engine] 初始化失败: $e');
      _engineReady = false;
    }
    _engineInitFailed = !_engineReady;
    if (!_engineReady) {
      String? why;
      try {
        why = engineStatus().error;
      } catch (_) {}
      debugPrint('[engine] 输出设备不可用（${why ?? "未知原因"}），继续使用系统播放器');
    }
    stateChanges.add(null);
    return _engineReady;
  }

  /// 设置页开关：切换时立即重载当前曲目以应用新后端。
  Future<void> setLocalEngine(bool v) async {
    _localEngine = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localEngineKey, v);
    if (v) {
      // 用户显式重新开启：允许对之前失败的初始化再试一次。
      _engineInitFailed = false;
      await _initLocalEngine();
    } else {
      if (_usingEngine) {
        try {
          engineStop();
        } catch (_) {}
      }
      _usingEngine = false;
      _engineStatus = null;
      _engineReady = false;
    }
    if (current != null && !isCasting) await _loadCurrent();
    stateChanges.add(null);
  }

  /// 周期性读取引擎状态（进度 / 结束 / 错误）。
  void _tickEngine() {
    if (!_usingEngine) return;
    EngineStatus st;
    try {
      st = engineStatus();
    } catch (e) {
      _fallbackFromEngine('$e');
      return;
    }
    _engineStatus = st;
    // seek 目标被解码线程追上（或在 3s 内没追上）后交还给真实进度。
    final seekTarget = _engineSeekTarget;
    if (seekTarget != null &&
        ((st.position - seekTarget).abs() < 0.5 ||
            DateTime.now().difference(_engineSeekAt) >
                const Duration(seconds: 3))) {
      _engineSeekTarget = null;
    }
    if (st.error != null) {
      _fallbackFromEngine(st.error!);
      return;
    }
    if (st.ended && !_engineEndedHandled) {
      _engineEndedHandled = true;
      unawaited(handleEnded());
    }
  }

  /// 本地引擎出错：本曲标记为不可用并立刻用 just_audio 重载，保证"点了就出声"。
  void _fallbackFromEngine(String reason) {
    final song = current;
    debugPrint('[engine] 回退系统播放器: $reason');
    _usingEngine = false;
    _engineStatus = null;
    _engineSeekTarget = null;
    _engineFailedSongId = song?.id;
    _lastError = reason;
    try {
      engineStop();
    } catch (_) {}
    if (song != null) unawaited(_loadCurrent());
    stateChanges.add(null);
  }

  /// 把当前 DSP 设置打包给引擎（预设 YAML / EQ / 交叉馈送 / RG / 淡入淡出）。
  Future<EngineOptions> _engineOptions(Song song) async {
    var yaml = '';
    final pid = _presetId;
    if (pid != null) {
      try {
        yaml = (await ApiClient.instance.getDspPreset(pid)).camillaYaml;
      } catch (_) {
        // 预设拉取失败：按直通处理，不影响起播。
      }
    }
    var eqJson = '';
    try {
      final eq = await ApiClient.instance.getEq();
      if (eq.profile.enabled) {
        eqJson = jsonEncode(eq.profile.toJson());
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    final crossfeed = (prefs.getDouble('fn_dsp_crossfeed') ?? 28).clamp(0.0, 100.0);
    final crossfeedJson = crossfeed > 0
        ? jsonEncode({
            'enabled': true,
            'amount': (crossfeed / 100).clamp(0.0, 0.5),
            'delay_ms': 0.3,
          })
        : '';
    final fadesOn = prefs.getBool('fn_dsp_fade') ?? true;
    final fadeIn = fadesOn ? (prefs.getDouble('fn_dsp_fade_in') ?? 800.0) : 0.0;
    final fadeOut = fadesOn ? (prefs.getDouble('fn_dsp_fade_out') ?? 1500.0) : 0.0;
    return EngineOptions(
      presetYaml: yaml,
      eqJson: eqJson,
      crossfeedJson: crossfeedJson,
      // ReplayGain 在引擎链里做（just_audio 只能靠音量衰减）；
      // 0 表示不调整，与后端 rg_mode=off 同义。
      rgGain: rgGainFor(song, _rgMode) ?? 0.0,
      fadeInMs: fadeIn,
      fadeOutMs: fadeOut,
      volume: _engineVolume,
    );
  }

  /// 引擎音量：RG 已在链内，这里只有用户音量与静音。
  double get _engineVolume => _muted ? 0.0 : _volume;

  /// 本地引擎加载（bypass 直出原始文件）。返回 false 表示应回退 just_audio。
  Future<bool> _loadWithEngine(Song song, int token, bool autoplay) async {
    try {
      final opts = await _engineOptions(song);
      if (token != _loadToken) return false;
      final url = ApiClient.instance.streamUrl(song.id, bypass: true);
      // 引擎与 just_audio 不能同时出声：先停系统播放器再交给引擎。
      try {
        await player.stop();
      } catch (_) {}
      if (token != _loadToken) return false;
      _usingEngine = true;
      _engineSeekTarget = null;
      _engineEndedHandled = false;
      _engineStatus = engineLoad(url: url, startSec: 0.0, opts: opts);
      if (autoplay) enginePlay();
      _lastError = null;
      return true;
    } catch (e) {
      _usingEngine = false;
      _engineStatus = null;
      _engineFailedSongId = song.id;
      debugPrint('[engine] 加载失败，回退系统播放器: $e');
      return false;
    }
  }

  void _broadcastState(bool playing) {
    // 多端同步关闭：不上报本端播放状态。
    if (!RuntimeConfig.instance.syncEnabled) return;
    if (_suppressUntil) {
      if (DateTime.now().isBefore(_suppressUntilTime)) return;
      _suppressUntil = false;
    }
    if (isCasting) return;
    final song = current;
    if (song == null) return;
    SyncClient.instance.send({
      'type': 'play_state',
      'song_id': song.id,
      'playing': playing,
      'position': positionSec,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---------------- 播放控制 ----------------

  /// 播放指定歌曲。
  Future<void> play(Song song, {int? presetId, String? quality}) async {
    if (presetId != null) _presetId = presetId;
    if (quality != null) _quality = quality;
    await playOne(song);
  }

  /// 设置整队播放（从某首开始）。
  Future<void> playList(List<Song> songs, int index) async {
    if (songs.isEmpty) return;
    _stopRoamInternal();
    _queue
      ..clear()
      ..addAll(songs);
    _index = index.clamp(0, songs.length - 1);
    current = _queue[_index];
    _lastError = null;
    _localActionUntil = DateTime.now().add(const Duration(seconds: 2));
    stateChanges.add(null);
    await _loadCurrent();
  }

  Future<void> playOne(Song song) async {
    _stopRoamInternal();
    _queue
      ..clear()
      ..add(song);
    _index = 0;
    current = song;
    _lastError = null;
    _localActionUntil = DateTime.now().add(const Duration(seconds: 2));
    stateChanges.add(null);
    await _loadCurrent();
  }

  // ---------------- 漫游 ----------------

  /// 开始漫游：mode = similar / taste / random。
  ///
  /// similar 以 [seedSongId]（默认当前歌曲）为种子，taste 依据收藏与播放历史，
  /// random 纯随机。成功后队列替换为这批歌曲并立即起播。
  Future<bool> startRoam(String mode, {int? seedSongId, int count = 20}) async {
    final seed = seedSongId ?? current?.id;
    try {
      final batch = await ApiClient.instance
          .fetchRoamSongs(mode: mode, seedSongId: seed, count: count);
      if (batch.isEmpty) {
        _lastError = '曲库中没有可漫游的歌曲';
        stateChanges.add(null);
        return false;
      }
      _roamMode = mode;
      _roamSeedId = seed;
      _roamSeen
        ..clear()
        ..addAll(batch.map((s) => s.id));
      _queue
        ..clear()
        ..addAll(batch);
      _index = 0;
      current = _queue.first;
      _lastError = null;
      _localActionUntil = DateTime.now().add(const Duration(seconds: 2));
      stateChanges.add(null);
      await _loadCurrent();
      return true;
    } catch (e) {
      _lastError = _describeError(e);
      stateChanges.add(null);
      return false;
    }
  }

  /// 结束漫游：保留当前队列与播放，只是不再自动续批。
  void stopRoam() {
    _stopRoamInternal();
    stateChanges.add(null);
  }

  void _stopRoamInternal() {
    _roamMode = null;
    _roamSeedId = null;
    _roamSeen.clear();
  }

  /// 续批：排除本会话已出过的歌曲，追加到队尾。
  Future<void> _extendRoam() async {
    final mode = _roamMode;
    if (mode == null) return;
    try {
      final batch = await ApiClient.instance.fetchRoamSongs(
        mode: mode,
        seedSongId: _roamSeedId,
        count: 20,
        exclude: _roamSeen.toList(),
      );
      final fresh = batch.where((s) => _roamSeen.add(s.id)).toList();
      if (fresh.isEmpty) {
        // 曲库已取尽：自动结束漫游，避免反复请求空批次。
        _stopRoamInternal();
        stateChanges.add(null);
        return;
      }
      _queue.addAll(fresh);
      // 长会话下限制队列长度：只丢弃当前曲目之前的旧条目。
      if (_queue.length > 500) {
        final drop = min(_queue.length - 400, _index);
        if (drop > 0) {
          _queue.removeRange(0, drop);
          _index -= drop;
        }
      }
    } catch (_) {
      // 续批失败时静默结束，下次手动开始漫游即可。
    }
  }

  /// 插入到「下一首」位置（曲目菜单「下一首播放」）。
  void playNext(Song song) {
    if (_queue.isEmpty) {
      playOne(song);
      return;
    }
    final at = (_index + 1).clamp(0, _queue.length);
    _queue.insert(at, song);
    stateChanges.add(null);
  }

  /// 移除队列中的某一项（队列页长按菜单 / 左滑）。
  Future<void> removeQueueAt(int i) async {
    if (i < 0 || i >= _queue.length) return;
    final removingCurrent = i == _index;
    _queue.removeAt(i);
    if (_queue.isEmpty) {
      _index = -1;
      current = null;
      if (_usingEngine) {
        _usingEngine = false;
        _engineStatus = null;
        try {
          engineStop();
        } catch (_) {}
      }
      await player.stop();
      stateChanges.add(null);
      return;
    }
    if (i < _index) _index--;
    if (removingCurrent) {
      _index = _index.clamp(0, _queue.length - 1);
      current = _queue[_index];
      await _loadCurrent();
      return;
    }
    stateChanges.add(null);
  }

  /// 队列内拖动排序。
  void moveQueue(int from, int to) {
    if (from < 0 || from >= _queue.length || to < 0 || to >= _queue.length) {
      return;
    }
    if (from == to) return;
    final song = _queue.removeAt(from);
    _queue.insert(to, song);
    if (_index == from) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
    stateChanges.add(null);
  }

  /// 清空队列（保留当前播放）。
  void clearQueue() {
    if (current == null) return;
    _queue
      ..clear()
      ..add(current!);
    _index = 0;
    stateChanges.add(null);
  }

  /// 单曲自然结束（本地播放 completed 或 DLNA 状态转为 STOPPED）。
  Future<void> handleEnded() async {
    if (_repeat == LoopMode.one && current != null) {
      if (isCasting) {
        await ApiClient.instance.dlnaSeek(0);
      } else if (_usingEngine) {
        engineSeek(secs: 0);
        enginePlay();
        _engineEndedHandled = false;
      } else {
        await player.seek(Duration.zero);
        _playIgnoringErrors();
      }
      return;
    }
    // 关闭自动播放下一首：停止并回到曲首（不自动切歌）。
    if (!RuntimeConfig.instance.autoPlayNext) {
      if (isCasting) {
        try {
          await ApiClient.instance.dlnaControl('stop');
        } catch (_) {}
      } else if (_usingEngine) {
        enginePause();
        engineSeek(secs: 0);
        _engineEndedHandled = false;
      } else {
        await player.pause();
        await player.seek(Duration.zero);
      }
      stateChanges.add(null);
      return;
    }
    await next();
  }

  /// 暂停（soft_mute 开启时先做约 20ms 增益斜坡淡出，暂停后恢复原音量）。
  Future<void> _pausePlayer() async {
    if (_usingEngine) {
      enginePause();
      _engineStatus = engineStatus();
      stateChanges.add(null);
      return;
    }
    final target = _effectiveVolume();
    if (RuntimeConfig.instance.softMute && target > 0) {
      for (var i = 1; i <= 3; i++) {
        await player.setVolume(target * (1 - i / 3));
        await Future.delayed(const Duration(milliseconds: 7));
      }
    }
    await player.pause();
    // 恢复原音量，便于下次播放（保持 muted/volume 既有语义）。
    await player.setVolume(target);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_shuffle && _queue.length > 1) {
      var n = _index;
      while (n == _index) {
        n = Random().nextInt(_queue.length);
      }
      _index = n;
    } else if (_index + 1 < _queue.length) {
      _index++;
    } else if (_roamMode != null) {
      // 漫游到队尾：自动续批后再前进一首。
      await _extendRoam();
      if (_index + 1 < _queue.length) {
        _index++;
      } else if (_repeat == LoopMode.all) {
        _index = 0;
      } else {
        return;
      }
    } else if (_repeat == LoopMode.all) {
      _index = 0;
    } else {
      return;
    }
    current = _queue[_index];
    stateChanges.add(null);
    await _loadCurrent();
  }

  Future<void> prev() async {
    // 播放超过 3 秒：先回到本曲开头（与常见播放器一致）。
    if (positionSec > 3) {
      await seek(0);
      return;
    }
    if (_index - 1 >= 0) {
      _index--;
      current = _queue[_index];
      stateChanges.add(null);
      await _loadCurrent();
    } else {
      await seek(0);
    }
  }

  /// 统一播放/暂停（自动区分本地 / DLNA）。
  Future<void> togglePlay() async {
    if (current == null) return;
    if (isCasting) {
      try {
        _dlnaStatus = await ApiClient.instance
            .dlnaControl(_dlnaStatus?.playing == true ? 'pause' : 'play');
        stateChanges.add(null);
      } catch (_) {}
      return;
    }
    if (isPlaying) {
      if (_usingEngine) {
        enginePause();
      } else {
        await _pausePlayer();
      }
    } else {
      if (_usingEngine) {
        enginePlay();
      } else {
        _playIgnoringErrors();
      }
    }
    stateChanges.add(null);
  }

  /// 统一 seek（秒）。
  Future<void> seek(double sec) async {
    if (isCasting) {
      try {
        _dlnaStatus = await ApiClient.instance.dlnaSeek(sec);
      } catch (_) {}
    } else if (_usingEngine) {
      _engineSeekTarget = sec;
      _engineSeekAt = DateTime.now();
      engineSeek(secs: sec);
      _engineEndedHandled = false;
      _engineStatus = engineStatus();
    } else {
      await player.seek(Duration(milliseconds: (sec * 1000).round()));
    }
    stateChanges.add(null);
  }

  /// 当前播放进度（秒）。
  double get positionSec {
    if (isCasting) return _dlnaStatus?.position ?? 0;
    if (_usingEngine) return _engineSeekTarget ?? _engineStatus?.position ?? 0;
    return player.position.inMilliseconds / 1000.0;
  }

  /// 当前时长（秒）。
  double get durationSec {
    if (isCasting) {
      return _dlnaStatus?.duration ?? current?.duration ?? 0;
    }
    if (_usingEngine) {
      final d = _engineStatus?.duration ?? 0;
      if (d > 0) return d;
      return current?.duration ?? 0;
    }
    final d = player.duration;
    if (d != null && d.inMilliseconds > 0) return d.inMilliseconds / 1000.0;
    return current?.duration ?? 0;
  }

  /// 已缓冲进度（秒）：锁屏/通知的缓冲条用，投屏时与播放进度一致。
  double get bufferedSec {
    if (isCasting) return positionSec;
    if (_usingEngine) return _engineStatus?.buffered ?? 0;
    return player.bufferedPosition.inMilliseconds / 1000.0;
  }

  bool get isPlaying => isCasting
      ? (_dlnaStatus?.playing ?? false)
      : (_usingEngine ? (_engineStatus?.playing ?? false) : player.playing);

  /// 继续播放（系统媒体控件 / 锁屏调用；已在播放则空操作）。
  Future<void> resume() async {
    if (current == null || isPlaying) return;
    if (isCasting) {
      try {
        _dlnaStatus = await ApiClient.instance.dlnaControl('play');
      } catch (_) {}
      stateChanges.add(null);
      return;
    }
    if (_usingEngine) {
      enginePlay();
      stateChanges.add(null);
      return;
    }
    _playIgnoringErrors();
  }

  /// 暂停（系统媒体控件 / 锁屏调用；未播放则空操作）。
  Future<void> pause() async {
    if (!isPlaying) return;
    if (isCasting) {
      try {
        _dlnaStatus = await ApiClient.instance.dlnaControl('pause');
      } catch (_) {}
      stateChanges.add(null);
      return;
    }
    if (_usingEngine) {
      enginePause();
      stateChanges.add(null);
      return;
    }
    await _pausePlayer();
    stateChanges.add(null);
  }

  // ---------------- 音量 / 随机 / 循环 ----------------

  /// 当前组合是否走服务端处理流（音效或有损档）。false 时为原始文件直出。
  bool get _serverProcessed =>
      _presetId != null || _effectiveQuality != 'lossless';

  /// 实际下发给服务端的音质档。
  /// Windows 端 just_audio 走 Media Foundation，不内置 Ogg/Opus 解复用器，
  /// 有损档（high / standard）能加载成功却解不出声音，表现为"点了没反应"。
  /// 因此 Windows 上统一回退到无损档，确保点播一定有声音。
  String get _effectiveQuality =>
      defaultTargetPlatform == TargetPlatform.windows && _quality != 'lossless'
          ? 'lossless'
          : _quality;

  /// 计算单曲 ReplayGain 线性增益（与后端 replaygain.rs 同口径）：
  /// gain = 10^(dB/20)，峰值存在时按 1/peak 封顶。
  static double? rgGainFor(Song? song, String mode) {
    if (song == null || mode == 'off') return null;
    var db = mode == 'album' ? song.rgAlbumGain : song.rgTrackGain;
    var peak = mode == 'album' ? song.rgAlbumPeak : song.rgTrackPeak;
    if (db == null && mode == 'album') {
      db = song.rgTrackGain;
      peak = song.rgTrackPeak;
    }
    if (db == null) return null;
    var gain = pow(10, db / 20).toDouble();
    if (peak != null && peak > 0) gain = min(gain, 1 / peak);
    return gain.clamp(0.0, 32.0).toDouble();
  }

  /// 实际写入播放器的音量：原始文件直出时 RG 只能在客户端以音量衰减实现
  ///（just_audio 无增益节点，正增益无法实现）；服务端处理流的 RG 已在音频里。
  double _effectiveVolume() {
    if (_muted) return 0;
    var v = _volume;
    if (!_serverProcessed && current != null) {
      final g = rgGainFor(current, _rgMode);
      if (g != null) v *= g.clamp(0.0, 1.0);
    }
    return v.clamp(0.0, 1.0);
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    if (_usingEngine) {
      engineSetVolume(volume: _engineVolume);
    } else {
      await player.setVolume(_effectiveVolume());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fn_audio_volume', _volume);
    stateChanges.add(null);
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_usingEngine) {
      engineSetVolume(volume: _engineVolume);
    } else {
      await player.setVolume(_effectiveVolume());
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fn_audio_muted', _muted);
    stateChanges.add(null);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    stateChanges.add(null);
  }

  void cycleRepeat() {
    _repeat = LoopMode.values[(_repeat.index + 1) % LoopMode.values.length];
    stateChanges.add(null);
  }

  /// design/v3 player 播放模式：列表循环 / 循环一次 / 随机播放。
  String get playMode =>
      _shuffle ? 'shuffle' : (_repeat == LoopMode.one ? 'one' : 'all');

  /// 单钮循环：列表循环 → 循环一次 → 随机播放 → 列表循环。
  void cyclePlayMode() {
    final next = switch (playMode) {
      'all' => 'one',
      'one' => 'shuffle',
      _ => 'all',
    };
    _shuffle = next == 'shuffle';
    _repeat = next == 'one' ? LoopMode.one : LoopMode.all;
    stateChanges.add(null);
  }

  // ---------------- 音效 / 音质 ----------------

  /// 切换音效预设（UI 下拉）。
  Future<void> setPreset(int? id) async {
    _presetId = id;
    await _persistPreset(id);
    if (current != null && !isCasting) await _loadCurrent();
    SyncClient.instance.send({'type': 'dsp_preset', 'preset_id': id});
  }

  int? get presetId => _presetId;
  String get quality => _quality;
  String get rgMode => _rgMode;

  Future<void> setQuality(String q) async {
    _quality = q;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fn_audio_quality', q);
    if (current != null && !isCasting) await _loadCurrent();
  }

  /// 切换 ReplayGain 模式：服务端处理流整段重载；直出流实时改音量衰减。
  Future<void> setRgMode(String mode) async {
    _rgMode = mode;
    final prefs = await SharedPreferences.getInstance();
    if (mode == 'off') {
      await prefs.remove('fn_audio_rg_mode');
    } else {
      await prefs.setString('fn_audio_rg_mode', mode);
    }
    if (current != null && !isCasting) {
      if (_serverProcessed) {
        await _loadCurrent();
      } else {
        await player.setVolume(_effectiveVolume());
      }
    }
    stateChanges.add(null);
  }

  // ---------------- DLNA 投屏 ----------------

  /// 投放到 DLNA 渲染器：暂停本机播放，由后端推送当前歌曲。
  Future<void> castTo(DlnaRenderer renderer) async {
    final song = current;
    if (song == null) return;
    _dlnaRenderer = renderer;
    _dlnaStatus = await ApiClient.instance.dlnaCast(renderer.id, song.id);
    _lastTransport = _dlnaStatus?.transport;
    await player.pause();
    startDlnaPoll();
    stateChanges.add(null);
  }

  /// 回到本机播放。
  Future<void> backToLocal() async {
    stopDlnaPoll();
    try {
      await ApiClient.instance.dlnaControl('local');
    } catch (_) {}
    final renderer = _dlnaRenderer;
    _dlnaRenderer = null;
    _dlnaStatus = null;
    _lastTransport = null;
    if (renderer != null && current != null) {
      await _loadCurrent();
    }
    stateChanges.add(null);
  }

  void startDlnaPoll() {
    _dlnaPoll?.cancel();
    _dlnaPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final st = await ApiClient.instance.dlnaStatus();
        if (st.rendererId == null) {
          // 投屏已结束（设备端停止）。
          if (_dlnaRenderer != null) {
            stopDlnaPoll();
            _dlnaRenderer = null;
            _dlnaStatus = null;
            stateChanges.add(null);
          }
          return;
        }
        final prev = _lastTransport;
        _dlnaStatus = st;
        _lastTransport = st.transport;
        // 自然播完：PLAYING -> STOPPED/PAUSED_PLAYBACK 且进度接近结尾。
        if (prev == 'PLAYING' &&
            (st.transport == 'STOPPED' || st.transport == 'PAUSED_PLAYBACK') &&
            st.position < 1.5) {
          await handleEnded();
        }
        stateChanges.add(null);
      } catch (_) {}
    });
  }

  void stopDlnaPoll() {
    _dlnaPoll?.cancel();
    _dlnaPoll = null;
  }

  // ---------------- 加载音源 ----------------

  Future<void> _loadCurrent({bool autoplay = true}) async {
    final song = current;
    if (song == null) return;
    if (isCasting) {
      // 投屏模式：新歌曲交给渲染器播放。
      try {
        _dlnaStatus =
            await ApiClient.instance.dlnaCast(_dlnaRenderer!.id, song.id);
        _lastTransport = _dlnaStatus?.transport;
      } catch (_) {}
      ApiClient.instance.recordHistory(song.id).catchError((_) {});
      stateChanges.add(null);
      return;
    }
    // 并发点播时只认最后一次：旧请求加载完也要丢弃，避免"点了 A 却放 B"。
    final token = ++_loadToken;
    // iOS 上引擎在首次播放时才建输出流（见 init），这里补一次初始化；
    // 初始化失败后不再每首歌重试，直接走系统播放器。
    if (_localEngine && _engineSupported && !_engineReady && !_engineInitFailed) {
      await _initLocalEngine();
      if (token != _loadToken) return;
    }
    // 本地引擎优先（全格式解码 + 本地 DSP）。本曲失败过的直接走系统播放器，
    // 避免在同一首上反复"失败→回退"导致听感抖动。
    if (_localEngine && _engineReady && _engineFailedSongId != song.id) {
      final ok = await _loadWithEngine(song, token, autoplay);
      if (token != _loadToken) return;
      if (ok) {
        ApiClient.instance.recordHistory(song.id).catchError((_) {});
        PlayLog.instance.record(song).catchError((_) {});
        stateChanges.add(null);
        return;
      }
    }
    // 系统播放器路径：先停掉可能还在出声的本地引擎，再换源。
    if (_usingEngine) {
      _usingEngine = false;
      _engineStatus = null;
      _engineSeekTarget = null;
      try {
        engineStop();
      } catch (_) {}
    }
    try {
      final url = ApiClient.instance.streamUrl(song.id,
          presetId: _presetId,
          quality: qualityStreamParam(_effectiveQuality),
          bitDepth: qualityBitDepth(_effectiveQuality),
          rgMode: _serverProcessed ? _rgMode : 'off');
      await player.setUrl(url);
      if (_debugRate) debugPrint('[rate] load url=$url');
      if (token != _loadToken) return;
      // 每次换源都显式把速率钉回 1.0：Windows 的 MediaPlayer 在 SetSource 后
      // 不会重置 PlaybackRate，上一次非 1.0 的速率会延续到新曲目（听感就是"莫名变快"）。
      await player.setSpeed(1.0);
      // 原始文件直出时 ReplayGain 在客户端以音量衰减实现。
      await player.setVolume(_effectiveVolume());
      if (autoplay) _playIgnoringErrors();
      _lastError = null;
      // 记录播放历史（失败不影响播放）
      ApiClient.instance.recordHistory(song.id).catchError((_) {});
      PlayLog.instance.record(song).catchError((_) {});
    } on PlayerInterruptedException {
      // 被更新的加载请求打断属于正常流程（见上方的 token 守卫）。
      return;
    } catch (e) {
      if (token != _loadToken) return;
      _lastError = _describeError(e);
    } finally {
      if (token == _loadToken) stateChanges.add(null);
    }
  }

  /// 起播并接住异步异常。
  /// 不能 await `player.play()`：它的 Future 要等整首播完（或暂停）才完成，
  /// await 会把"点击播放"变成"点击后卡住"。
  void _playIgnoringErrors() {
    unawaited(player.play().catchError((Object e) {
      _lastError = _describeError(e);
      stateChanges.add(null);
    }));
  }

  /// 只返回错误细节，前缀文案由页面按当前语言拼装（见 `FnL10n`）。
  String _describeError(Object e) {
    if (e is PlayerException) {
      final msg = e.message;
      if (msg != null && msg.isNotEmpty) return msg;
      return 'code ${e.code}';
    }
    return '$e';
  }
}

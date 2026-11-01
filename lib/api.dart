import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';

/// 后端 API 客户端：JWT 持久化、401 处理、音频流 URL 构造。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// 用户在 App 内手动输入的服务器地址（SharedPreferences 键）。
  static const String baseUrlKey = 'fn_audio_base';

  /// 桌面（Windows/Linux/macOS）与 iOS 模拟器默认访问本机后端；Android 模拟器用
  /// 10.0.2.2 访问宿主机。iOS 真机的 127.0.0.1 指向手机自身，需在登录页填写
  /// 局域网内服务器地址。编译期可用 --dart-define=FN_AUDIO_BASE=... 覆盖。
  static String get platformDefault {
    const defined = String.fromEnvironment('FN_AUDIO_BASE', defaultValue: '');
    if (defined.isNotEmpty) return defined;
    try {
      if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isIOS) {
        return 'http://127.0.0.1:8080';
      }
    } catch (_) {
      // Web 等不支持 dart:io 的环境忽略。
    }
    return 'http://10.0.2.2:8080'; // Android 模拟器访问宿主机
  }

  /// 用户手动设置并持久化的地址（null 表示未设置，回退平台默认）。
  String? _customBase;

  /// 当前生效的后端地址：手动输入 > 编译期 dart-define > 平台默认。
  String get baseUrl => (_customBase != null && _customBase!.isNotEmpty)
      ? _customBase!
      : platformDefault;

  /// 手动输入是否生效（用于"恢复默认"）。
  bool get hasCustomBase => _customBase != null && _customBase!.isNotEmpty;

  final Dio dio = Dio(BaseOptions(
    baseUrl: platformDefault,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String? _token;
  String? username;
  bool isAdmin = false;

  String? get token => _token;

  /// 校验服务器地址：必须是 http(s) 且包含主机名；返回规范化结果（去尾部 /）。
  ///
  /// 非法输入抛 [FormatException]，`message` 为错误码（`empty` / `scheme` /
  /// `host`），由界面按当前语言翻译，避免把文案硬编码在数据层。
  static String normalizeBaseUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) throw const FormatException('empty');
    final uri = Uri.tryParse(v);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('scheme');
    }
    if (uri.host.isEmpty) {
      throw const FormatException('host');
    }
    // 去掉末尾斜杠，避免拼出 //api/...
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  /// 保存用户手动输入的服务器地址（null 或空串表示恢复默认）。
  Future<void> setBaseUrl(String? raw) async {
    String? normalized;
    if (raw != null && raw.trim().isNotEmpty) {
      normalized = normalizeBaseUrl(raw);
    }
    _customBase = normalized;
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(baseUrlKey);
    } else {
      await prefs.setString(baseUrlKey, normalized);
    }
    dio.options.baseUrl = baseUrl;
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(baseUrlKey);
    _customBase = (saved != null && saved.isNotEmpty) ? saved : null;
    dio.options.baseUrl = baseUrl;
    _token = prefs.getString('token');
    username = prefs.getString('username');
    isAdmin = prefs.getBool('is_admin') ?? false;
  }

  Future<void> login(String username, String password) async {
    final res = await dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    _token = data['token'] as String;
    this.username = data['username'] as String;
    isAdmin = data['is_admin'] as bool? ?? false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token!);
    await prefs.setString('username', this.username!);
    await prefs.setBool('is_admin', isAdmin);
  }

  Future<void> logout() async {
    _token = null;
    username = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('username');
    await prefs.remove('is_admin');
  }

  Future<List<Song>> fetchSongs({String? q}) async {
    final res = await dio.get('/api/library/songs',
        queryParameters: {'page': 1, 'page_size': 200, if (q != null) 'q': q},
        options: Options(headers: _authHeader()));
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Song.fromJson).toList();
  }

  /// 音频流地址（just_audio 无法自定义 Header，使用 query token）。
  /// [rgMode] 仅在服务端整段处理（音效/有损档）时传入；原始文件直出由客户端处理。
  /// [bypass] 为 true 时服务端跳过一切 DSP 与转码直接回原始文件字节（含 DSD），
  /// 供 App 本地引擎（全格式解码 + 本地 DSP）使用。
  String streamUrl(int songId,
      {int? presetId,
      String? quality,
      String? bitDepth,
      String? rgMode,
      bool bypass = false}) {
    final q = <String, String>{'token': _token ?? ''};
    if (bypass) {
      q['bypass'] = '1';
    } else {
      if (presetId != null) q['preset_id'] = presetId.toString();
      if (quality != null) q['quality'] = quality;
      if (bitDepth != null) q['bit_depth'] = bitDepth;
      if (rgMode != null && rgMode != 'off') q['rg_mode'] = rgMode;
    }
    final query = q.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$baseUrl/api/stream/$songId?$query';
  }

  Future<LyricData> fetchLyric(int songId) async {
    final res = await dio.get('/api/library/lyric/$songId',
        options: Options(headers: _authHeader()));
    return LyricData.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<DspPreset>> fetchDspPresets() async {
    final res = await dio.get('/api/dsp/presets',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(DspPreset.fromJson)
        .toList();
  }

  // ---------- Phase5：歌单 / 收藏 / 历史 ----------

  Future<Song> fetchSong(int id) async {
    final res = await dio.get('/api/library/songs/$id',
        options: Options(headers: _authHeader()));
    return Song.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Playlist>> fetchPlaylists() async {
    final res = await dio.get('/api/playlists',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(Playlist.fromJson)
        .toList();
  }

  Future<Playlist> createPlaylist(String name) async {
    final res = await dio.post('/api/playlists',
        data: {'name': name}, options: Options(headers: _authHeader()));
    return Playlist.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Playlist> fetchPlaylistDetail(int id) async {
    final res = await dio.get('/api/playlists/$id',
        options: Options(headers: _authHeader()));
    return Playlist.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deletePlaylist(int id) async {
    await dio.delete('/api/playlists/$id',
        options: Options(headers: _authHeader()));
  }

  Future<void> addPlaylistTrack(int playlistId, int songId) async {
    await dio.post('/api/playlists/$playlistId/track',
        data: {'song_id': songId}, options: Options(headers: _authHeader()));
  }

  Future<void> removePlaylistTrack(int playlistId, int songId) async {
    await dio.delete('/api/playlists/$playlistId/track/$songId',
        options: Options(headers: _authHeader()));
  }

  Future<List<Song>> fetchFavorites() async {
    final res = await dio.get('/api/favorites',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(SongRef.fromJsonAsSong)
        .toList();
  }

  Future<void> addFavorite(int songId) async {
    await dio.post('/api/favorites/$songId',
        options: Options(headers: _authHeader()));
  }

  Future<void> removeFavorite(int songId) async {
    await dio.delete('/api/favorites/$songId',
        options: Options(headers: _authHeader()));
  }

  Future<List<Song>> fetchHistory({int limit = 50}) async {
    final res = await dio.get('/api/history',
        queryParameters: {'limit': limit},
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(SongRef.fromJsonAsSong)
        .toList();
  }

  Future<void> recordHistory(int songId) async {
    await dio.post('/api/history',
        data: {'song_id': songId}, options: Options(headers: _authHeader()));
  }

  // ---------- Phase6：分类浏览 / 关注歌手 / 漫游 / 每日推荐 ----------

  /// 专辑详情（含按碟号、音轨号排序的歌曲）。
  Future<AlbumDetail> fetchAlbumDetail(int albumId) async {
    final res = await dio.get('/api/library/albums/$albumId',
        options: Options(headers: _authHeader()));
    return AlbumDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// 艺人详情（名称、年份、专辑、风格）。
  Future<ArtistDetail> fetchArtistDetail(String name) async {
    final res = await dio.get(
        '/api/library/artists/${Uri.encodeComponent(name)}',
        options: Options(headers: _authHeader()));
    return ArtistDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// 风格列表（歌曲数降序）。
  Future<List<GenreInfo>> fetchGenres() async {
    final res = await dio.get('/api/library/genres',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(GenreInfo.fromJson)
        .toList();
  }

  /// 单个风格下的全部歌曲。
  Future<GenreDetail> fetchGenreDetail(String name) async {
    final res = await dio
        .get('/api/library/genres/${Uri.encodeComponent(name)}',
            options: Options(headers: _authHeader()));
    return GenreDetail.fromJson(res.data as Map<String, dynamic>);
  }

  /// 聚合列表：by = album / artist / genre。
  Future<AggregatePage> fetchAggregate({
    String by = 'album',
    String sort = 'name',
    int page = 1,
    int pageSize = 100,
  }) async {
    final res = await dio.get('/api/library/aggregate', queryParameters: {
      'by': by,
      'sort': sort,
      'page': page,
      'page_size': pageSize,
    }, options: Options(headers: _authHeader()));
    return AggregatePage.fromJson(res.data as Map<String, dynamic>);
  }

  /// 关注歌手列表。
  Future<List<FollowedArtist>> fetchFollowedArtists() async {
    final res = await dio.get('/api/artist-follows',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(FollowedArtist.fromJson)
        .toList();
  }

  Future<void> followArtist(String name) async {
    await dio.post('/api/artist-follows/${Uri.encodeComponent(name)}',
        options: Options(headers: _authHeader()));
  }

  Future<void> unfollowArtist(String name) async {
    await dio.delete('/api/artist-follows/${Uri.encodeComponent(name)}',
        options: Options(headers: _authHeader()));
  }

  /// 漫游下一批歌曲（mode = similar / taste / random）。
  Future<List<Song>> fetchRoamSongs({
    int? seedSongId,
    String mode = 'random',
    int count = 20,
    List<int> exclude = const [],
  }) async {
    final res = await dio.get('/api/roam/next', queryParameters: {
      if (seedSongId != null) 'seed_song_id': seedSongId,
      'mode': mode,
      'count': count,
      if (exclude.isNotEmpty) 'exclude': exclude.join(','),
    }, options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(Song.fromJson)
        .toList();
  }

  /// 每日推荐（[refresh] 为 true 时手动换一批）。
  Future<DailyRecommendations> fetchDailyRecommendations(
      {bool refresh = false}) async {
    final res = await dio.get('/api/recommendations/daily', queryParameters: {
      if (refresh) 'refresh': 1,
    }, options: Options(headers: _authHeader()));
    return DailyRecommendations.fromJson(res.data as Map<String, dynamic>);
  }

  /// 设置歌单封面（null 清除，回退首曲封面）。
  Future<void> setPlaylistCover(int playlistId, int? songId) async {
    await dio.put('/api/playlists/$playlistId/cover',
        data: {'song_id': songId}, options: Options(headers: _authHeader()));
  }

  /// 调整歌单曲目顺序（传入完整顺序）。
  Future<void> reorderPlaylist(int playlistId, List<int> songIds) async {
    await dio.put('/api/playlists/$playlistId/order',
        data: {'song_ids': songIds}, options: Options(headers: _authHeader()));
  }

  /// 构造 WebSocket 多端同步地址（ws/wss）。
  String syncWsUrl() {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}/api/ws?token=${Uri.encodeComponent(_token ?? '')}';
  }

  /// 封面图地址（Image.network 无法带 Header，使用 query token）。
  String coverUrl(int songId, {String? kind}) {
    final k = kind == null ? '' : '&kind=$kind';
    return '$baseUrl/api/library/cover/$songId?token=${Uri.encodeComponent(_token ?? '')}$k';
  }

  // ---------- DLNA 投屏（控制点） ----------

  Future<List<DlnaRenderer>> dlnaRenderers({bool refresh = false}) async {
    final res = await dio.get('/api/dlna/renderers',
        queryParameters: {if (refresh) 'refresh': 1},
        options: Options(headers: _authHeader()));
    return (res.data['renderers'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(DlnaRenderer.fromJson)
        .toList();
  }

  Future<DlnaStatus> dlnaCast(String rendererId, int songId) async {
    final res = await dio.post('/api/dlna/cast',
        data: {'renderer_id': rendererId, 'song_id': songId},
        options: Options(headers: _authHeader()));
    return DlnaStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DlnaStatus> dlnaControl(String action) async {
    final res = await dio.post('/api/dlna/$action',
        options: Options(headers: _authHeader()));
    return DlnaStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DlnaStatus> dlnaSeek(double position) async {
    final res = await dio.post('/api/dlna/seek',
        data: {'position': position}, options: Options(headers: _authHeader()));
    return DlnaStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DlnaStatus> dlnaSetVolume(int volume) async {
    final res = await dio.post('/api/dlna/volume',
        data: {'volume': volume}, options: Options(headers: _authHeader()));
    return DlnaStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DlnaStatus> dlnaStatus() async {
    final res = await dio.get('/api/dlna/status',
        options: Options(headers: _authHeader()));
    return DlnaStatus.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 歌词编辑 ----------

  /// 读取歌词（含原始 LRC 文本，供编辑使用）。
  Future<LyricData> fetchLyricRaw(int songId) async {
    final res = await dio.get('/api/library/lyric/$songId',
        options: Options(headers: _authHeader()));
    return LyricData.fromJson(res.data as Map<String, dynamic>);
  }

  /// 保存手动编辑的歌词（来源标记为 user）。
  Future<LyricData> saveLyric(int songId, String rawLrc) async {
    final res = await dio.put('/api/library/lyric/$songId',
        data: {'raw_lrc': rawLrc}, options: Options(headers: _authHeader()));
    return LyricData.fromJson(res.data as Map<String, dynamic>);
  }

  /// 上传 LRC 文件（multipart）。
  Future<LyricData> uploadLyric(
      int songId, String filename, List<int> bytes) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await dio.post('/api/library/lyric/upload/$songId',
        data: form, options: Options(headers: _authHeader()));
    return LyricData.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 曲库扫描 / 刮削 ----------

  /// 查询扫描运行状态与上次结果。
  Future<ScanStatus> scanStatus() async {
    final res = await dio.get('/api/library/scan/status',
        options: Options(headers: _authHeader()));
    return ScanStatus.fromJson(res.data as Map<String, dynamic>);
  }

  /// 触发曲库扫描（[force] 为 true 时全量重扫；管理员）。
  /// 后端改为后台任务，立即返回当前（running）状态。
  Future<ScanStatus> rescan({bool force = false}) async {
    final res = await dio.post('/api/library/rescan',
        data: {'force': force}, options: Options(headers: _authHeader()));
    return ScanStatus.fromJson(res.data as Map<String, dynamic>);
  }

  /// 列出全部扫描目录。
  Future<List<ScanRoot>> listScanRoots() async {
    final res = await dio.get('/api/library/roots',
        options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(ScanRoot.fromJson)
        .toList();
  }

  /// 新增扫描目录（管理员）。
  Future<ScanRoot> addScanRoot(String path) async {
    final res = await dio.post('/api/library/roots',
        data: {'path': path}, options: Options(headers: _authHeader()));
    return ScanRoot.fromJson(res.data as Map<String, dynamic>);
  }

  /// 删除扫描目录（管理员）。
  Future<void> deleteScanRoot(int id) async {
    await dio.delete('/api/library/roots/$id',
        options: Options(headers: _authHeader()));
  }

  // ---------- 系统配置 ----------

  /// 读取系统配置（所有登录用户可读）。
  Future<SystemConfig> getSystemConfig() async {
    final res = await dio.get('/api/system/config',
        options: Options(headers: _authHeader()));
    return SystemConfig.fromJson(res.data as Map<String, dynamic>);
  }

  /// 更新系统配置（管理员）。
  Future<SystemConfig> updateSystemConfig(Map<String, dynamic> config) async {
    final res = await dio.put('/api/system/config',
        data: {'config': config}, options: Options(headers: _authHeader()));
    return SystemConfig.fromJson(res.data as Map<String, dynamic>);
  }

  /// 单曲联网刮削元数据 / 歌词 / 封面。
  Future<ScrapeResult> scrapeSong(int songId) async {
    final res = await dio.post('/api/library/scrape/$songId',
        options: Options(headers: _authHeader()));
    return ScrapeResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// 批量刮削（[songIds] 为 null 时全库）。
  Future<List<ScrapeResult>> scrapeBatch({List<int>? songIds}) async {
    final res = await dio.post('/api/library/scrape/batch',
        data: {'song_ids': songIds}, options: Options(headers: _authHeader()));
    return (res.data as List)
        .cast<Map<String, dynamic>>()
        .map(ScrapeResult.fromJson)
        .toList();
  }

  // ---------- DSP 音效预设 CRUD ----------

  Future<DspPresetDetail> getDspPreset(int id) async {
    final res = await dio.get('/api/dsp/presets/$id',
        options: Options(headers: _authHeader()));
    return DspPresetDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DspPresetDetail> createDspPreset(
      {required String name,
      String? description,
      required String camillaYaml}) async {
    final res = await dio.post('/api/dsp/presets',
        data: {
          'name': name,
          'description': description,
          'camilla_yaml': camillaYaml
        },
        options: Options(headers: _authHeader()));
    return DspPresetDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DspPresetDetail> updateDspPreset(int id,
      {required String name,
      String? description,
      required String camillaYaml}) async {
    final res = await dio.put('/api/dsp/presets/$id',
        data: {
          'name': name,
          'description': description,
          'camilla_yaml': camillaYaml
        },
        options: Options(headers: _authHeader()));
    return DspPresetDetail.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteDspPreset(int id) async {
    await dio.delete('/api/dsp/presets/$id',
        options: Options(headers: _authHeader()));
  }

  // ---------- EQ / GEQ / AutoEq ----------

  Future<EqState> getEq() async {
    final res =
        await dio.get('/api/dsp/eq', options: Options(headers: _authHeader()));
    return EqState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EqState> putEq(EqProfile profile) async {
    final res = await dio.put('/api/dsp/eq',
        data: profile.toJson(), options: Options(headers: _authHeader()));
    return EqState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> clearEq() async {
    await dio.delete('/api/dsp/eq', options: Options(headers: _authHeader()));
  }

  Future<EqResponse> getEqResponse({int points = 96}) async {
    final res = await dio.get('/api/dsp/eq/response',
        queryParameters: {'points': points},
        options: Options(headers: _authHeader()));
    return EqResponse.fromJson(res.data as Map<String, dynamic>);
  }

  Future<GeqMeta> getGeqMeta() async {
    final res = await dio.get('/api/dsp/geq/meta',
        options: Options(headers: _authHeader()));
    return GeqMeta.fromJson(res.data as Map<String, dynamic>);
  }

  Future<GeqGrid> getGeqGrid(int bands) async {
    final res = await dio.get('/api/dsp/geq/grid',
        queryParameters: {'bands': bands},
        options: Options(headers: _authHeader()));
    return GeqGrid.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EqState> putGeq(int bands, List<double> gainsDb,
      {bool enabled = true}) async {
    final res = await dio.put('/api/dsp/geq',
        data: {'bands': bands, 'gains_db': gainsDb, 'enabled': enabled},
        options: Options(headers: _authHeader()));
    return EqState.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AutoEqResult> importAutoEq(String text,
      {String? name, bool apply = true}) async {
    final res = await dio.post('/api/dsp/eq/autoeq',
        data: {'text': text, 'name': name, 'apply': apply},
        options: Options(headers: _authHeader()));
    return AutoEqResult.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 淡入淡出 ----------

  Future<FadeSettings> getFades() async {
    final res = await dio.get('/api/dsp/fades',
        options: Options(headers: _authHeader()));
    return FadeSettings.fromJson(res.data as Map<String, dynamic>);
  }

  Future<FadeSettings> putFades(FadeSettings s) async {
    final res = await dio.put('/api/dsp/fades',
        data: s.toJson(), options: Options(headers: _authHeader()));
    return FadeSettings.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- ReplayGain 实测 ----------

  Future<ReplayGainStatus> getReplayGainStatus() async {
    final res = await dio.get('/api/library/replaygain/status',
        options: Options(headers: _authHeader()));
    return ReplayGainStatus.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TrackAnalysis> analyzeReplayGain(int songId,
      {bool force = false}) async {
    final res = await dio.post('/api/library/replaygain/$songId',
        data: {'force': force}, options: Options(headers: _authHeader()));
    return TrackAnalysis.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AnalysisSummary> analyzeReplayGainBatch(
      {String scope = 'missing', bool force = false, int? limit}) async {
    final res = await dio.post('/api/library/replaygain/analyze',
        data: {
          'scope': scope,
          'force': force,
          if (limit != null) 'limit': limit
        },
        options: Options(headers: _authHeader()));
    return AnalysisSummary.fromJson(res.data as Map<String, dynamic>);
  }

  Map<String, String> _authHeader() =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};
}

/// DLNA 渲染器（远端播放设备）。
class DlnaRenderer {
  final String id;
  final String name;
  final String location;
  DlnaRenderer({required this.id, required this.name, required this.location});

  factory DlnaRenderer.fromJson(Map<String, dynamic> j) => DlnaRenderer(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '未知设备') as String,
        location: (j['location'] ?? '') as String,
      );
}

/// DLNA 投屏状态。
class DlnaStatus {
  final String? rendererId;
  final int? songId;
  final String transport;
  final double position;
  final double duration;
  final int volume;

  DlnaStatus({
    this.rendererId,
    this.songId,
    required this.transport,
    required this.position,
    required this.duration,
    required this.volume,
  });

  bool get playing => transport == 'PLAYING';

  factory DlnaStatus.fromJson(Map<String, dynamic> j) => DlnaStatus(
        rendererId: j['renderer_id'] as String?,
        songId: (j['song_id'] as num?)?.toInt(),
        transport: (j['transport'] ?? 'STOPPED') as String,
        position: (j['position'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        volume: (j['volume'] as num?)?.toInt() ?? 0,
      );
}

/// 结构化歌词行（毫秒时间轴；纯文本歌词 timeMs 为 null）。
class LyricLine {
  final int? timeMs;
  final String text;
  LyricLine({required this.timeMs, required this.text});

  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(
        timeMs: j['time_ms'] as int?,
        text: (j['text'] ?? '') as String,
      );
}

class LyricData {
  final int? songId;
  final String source;
  final String? rawLrc;
  final String? updatedAt;
  final List<LyricLine> lines;
  LyricData({
    this.songId,
    required this.source,
    this.rawLrc,
    this.updatedAt,
    required this.lines,
  });

  factory LyricData.fromJson(Map<String, dynamic> j) {
    final raw = (j['lines'] as List? ?? const []);
    return LyricData(
      songId: (j['song_id'] as num?)?.toInt(),
      source: (j['source'] ?? 'none') as String,
      rawLrc: j['raw_lrc'] as String?,
      updatedAt: j['updated_at'] as String?,
      lines: raw.cast<Map<String, dynamic>>().map(LyricLine.fromJson).toList(),
    );
  }
}

/// 歌词来源展示标签。
String lyricSourceLabel(AppLocalizations l, String source) {
  switch (source) {
    case 'user':
      return l.lyricSourceUser;
    case 'embedded':
      return l.lyricSourceEmbedded;
    case 'file':
      return l.lyricSourceFile;
    case 'network':
      return l.lyricSourceNetwork;
    default:
      return l.lyricSourceNone;
  }
}

class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final double? duration;
  final String? codec;
  final int? sampleRate;
  final int? channels;
  final int? bitDepth;
  final bool hasLyric;
  final double? rgTrackGain;
  final double? rgTrackPeak;
  final double? rgAlbumGain;
  final double? rgAlbumPeak;
  final double? rgTrackTruePeak;
  final double? rgAlbumTruePeak;

  /// 增益来源：tag = 文件标签；analysis = 服务端实测；null = 无。
  final String? rgSource;

  /// 发行年份（缺失为 null，界面显示「未知年份」）。
  final int? year;

  /// 风格（缺失为 null，界面显示「未知风格」）。
  final String? genre;

  /// 专辑内音轨号 / 碟号（用于专辑页排序展示）。
  final int? trackNo;
  final int? discNo;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.bitDepth,
    required this.hasLyric,
    required this.rgTrackGain,
    required this.rgTrackPeak,
    required this.rgAlbumGain,
    required this.rgAlbumPeak,
    this.rgTrackTruePeak,
    this.rgAlbumTruePeak,
    this.rgSource,
    this.year,
    this.genre,
    this.trackNo,
    this.discNo,
  });

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '未知艺术家') as String,
        album: (j['album'] ?? '未知专辑') as String,
        duration: (j['duration'] as num?)?.toDouble(),
        codec: j['codec'] as String?,
        sampleRate: (j['sample_rate'] as num?)?.toInt(),
        channels: (j['channels'] as num?)?.toInt(),
        bitDepth: (j['bit_depth'] as num?)?.toInt(),
        hasLyric: (j['has_lyric'] as bool?) ?? false,
        rgTrackGain: (j['rg_track_gain'] as num?)?.toDouble(),
        rgTrackPeak: (j['rg_track_peak'] as num?)?.toDouble(),
        rgAlbumGain: (j['rg_album_gain'] as num?)?.toDouble(),
        rgAlbumPeak: (j['rg_album_peak'] as num?)?.toDouble(),
        rgTrackTruePeak: (j['rg_track_true_peak'] as num?)?.toDouble(),
        rgAlbumTruePeak: (j['rg_album_true_peak'] as num?)?.toDouble(),
        rgSource: j['rg_source'] as String?,
        year: (j['year'] as num?)?.toInt(),
        genre: j['genre'] as String?,
        trackNo: (j['track_no'] as num?)?.toInt(),
        discNo: (j['disc_no'] as num?)?.toInt(),
      );

  /// 是否为 Hi-Res（采样率 > 48k 或位深 > 16）。
  bool get isHiRes => (sampleRate ?? 0) > 48000 || (bitDepth ?? 0) > 16;

  /// 是否为 DSD 编码。
  bool get isDsd => (codec ?? '').toUpperCase().contains('DSD');

  /// 是否为有损编码。
  bool get isLossy {
    final c = (codec ?? '').toLowerCase();
    if (c.isEmpty) return false;
    const lossless = ['flac', 'alac', 'ape', 'wav', 'dsd', 'aiff', 'pcm'];
    return !lossless.any(c.contains);
  }
}

class DspPreset {
  final int id;
  final String name;
  final String? description;
  final bool isSystem;

  DspPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
  });

  factory DspPreset.fromJson(Map<String, dynamic> j) => DspPreset(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        isSystem: (j['is_system'] as bool?) ?? false,
      );
}

/// 歌单里的歌曲引用（/api/playlists、/api/favorites、/api/history 返回）。
class SongRef {
  static Song fromJsonAsSong(Map<String, dynamic> j) => Song(
        id: j['id'] as int,
        title: (j['title'] ?? '') as String,
        artist: (j['artist'] ?? '未知艺术家') as String,
        album: (j['album'] ?? '未知专辑') as String,
        duration: (j['duration'] as num?)?.toDouble(),
        codec: null,
        sampleRate: null,
        channels: null,
        bitDepth: null,
        hasLyric: false,
        rgTrackGain: null,
        rgTrackPeak: null,
        rgAlbumGain: null,
        rgAlbumPeak: null,
      );
}

class Playlist {
  final int id;
  final String name;
  final String? createdAt;
  final int songCount;
  final int? coverSongId;
  final List<Song> tracks;

  Playlist({
    required this.id,
    required this.name,
    this.createdAt,
    this.songCount = 0,
    this.coverSongId,
    this.tracks = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        createdAt: j['created_at'] as String?,
        songCount: (j['song_count'] as int?) ?? 0,
        coverSongId: (j['cover_song_id'] as num?)?.toInt(),
        tracks: (j['tracks'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SongRef.fromJsonAsSong)
            .toList(),
      );
}

/// 专辑详情。
class AlbumDetail {
  final int id;
  final String name;
  final String artist;
  final int songCount;
  final bool hasCover;
  final List<Song> songs;

  AlbumDetail({
    required this.id,
    required this.name,
    required this.artist,
    required this.songCount,
    required this.hasCover,
    required this.songs,
  });

  factory AlbumDetail.fromJson(Map<String, dynamic> j) => AlbumDetail(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '') as String,
        artist: (j['artist'] ?? '') as String,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        hasCover: (j['has_cover'] as bool?) ?? false,
        songs: (j['songs'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Song.fromJson)
            .toList(),
      );
}

/// 艺人详情（关注状态 + 全部歌曲）。
class ArtistDetail {
  final String name;
  final int songCount;
  final int albumCount;
  final bool followed;
  final List<Song> songs;

  ArtistDetail({
    required this.name,
    required this.songCount,
    required this.albumCount,
    required this.followed,
    required this.songs,
  });

  factory ArtistDetail.fromJson(Map<String, dynamic> j) => ArtistDetail(
        name: (j['name'] ?? '') as String,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
        followed: (j['followed'] as bool?) ?? false,
        songs: (j['songs'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Song.fromJson)
            .toList(),
      );
}

/// 风格分组统计。
class GenreInfo {
  final String name;
  final int songCount;
  final int albumCount;

  GenreInfo({
    required this.name,
    required this.songCount,
    required this.albumCount,
  });

  factory GenreInfo.fromJson(Map<String, dynamic> j) => GenreInfo(
        name: (j['name'] ?? '') as String,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
      );
}

/// 单个风格下的歌曲。
class GenreDetail {
  final String name;
  final int songCount;
  final List<Song> songs;

  GenreDetail({required this.name, required this.songCount, required this.songs});

  factory GenreDetail.fromJson(Map<String, dynamic> j) => GenreDetail(
        name: (j['name'] ?? '') as String,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        songs: (j['songs'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Song.fromJson)
            .toList(),
      );
}

/// 聚合列表条目（专辑 / 艺人 / 风格）。
class AggregateItem {
  final int? id;
  final String name;
  final String? subtitle;
  final int songCount;
  final int albumCount;
  final bool followed;

  AggregateItem({
    this.id,
    required this.name,
    this.subtitle,
    required this.songCount,
    required this.albumCount,
    required this.followed,
  });

  factory AggregateItem.fromJson(Map<String, dynamic> j) => AggregateItem(
        id: (j['id'] as num?)?.toInt(),
        name: (j['name'] ?? '') as String,
        subtitle: j['subtitle'] as String?,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
        followed: (j['followed'] as bool?) ?? false,
      );
}

class AggregatePage {
  final List<AggregateItem> items;
  final int total;
  final int page;
  final int pageSize;

  AggregatePage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory AggregatePage.fromJson(Map<String, dynamic> j) => AggregatePage(
        items: (j['items'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(AggregateItem.fromJson)
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['page_size'] as num?)?.toInt() ?? 0,
      );
}

/// 已关注歌手。
class FollowedArtist {
  final String name;
  final String createdAt;
  final int songCount;
  final int albumCount;

  FollowedArtist({
    required this.name,
    required this.createdAt,
    required this.songCount,
    required this.albumCount,
  });

  factory FollowedArtist.fromJson(Map<String, dynamic> j) => FollowedArtist(
        name: (j['name'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
        songCount: (j['song_count'] as num?)?.toInt() ?? 0,
        albumCount: (j['album_count'] as num?)?.toInt() ?? 0,
      );
}

/// 一条每日推荐（歌曲 + 推荐理由）。
class DailyRecItem {
  final Song song;
  final String reason;
  DailyRecItem({required this.song, required this.reason});

  factory DailyRecItem.fromJson(Map<String, dynamic> j) => DailyRecItem(
        song: Song.fromJson((j['song'] as Map).cast<String, dynamic>()),
        reason: (j['reason'] ?? '') as String,
      );
}

class DailyRecommendations {
  final String date;
  final List<DailyRecItem> items;
  DailyRecommendations({required this.date, required this.items});

  factory DailyRecommendations.fromJson(Map<String, dynamic> j) =>
      DailyRecommendations(
        date: (j['date'] ?? '') as String,
        items: (j['items'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DailyRecItem.fromJson)
            .toList(),
      );
}

/// DSP 预设详情（含 CamillaDSP YAML 定义）。
class DspPresetDetail {
  final int id;
  final String name;
  final String? description;
  final bool isSystem;
  final String camillaYaml;
  final String? createdAt;

  DspPresetDetail({
    required this.id,
    required this.name,
    this.description,
    required this.isSystem,
    required this.camillaYaml,
    this.createdAt,
  });

  factory DspPresetDetail.fromJson(Map<String, dynamic> j) => DspPresetDetail(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        isSystem: (j['is_system'] as bool?) ?? false,
        camillaYaml: (j['camilla_yaml'] ?? '') as String,
        createdAt: j['created_at'] as String?,
      );
}

// ---------- EQ / GEQ ----------

/// 均衡器频段类型。
const List<String> kEqBandTypes = [
  'peak',
  'low_shelf',
  'high_shelf',
  'low_pass',
  'high_pass',
  'notch',
  'band_pass',
  'all_pass',
];

/// 频段类型的中文/简称标签。
String eqBandTypeLabel(String type) {
  switch (type) {
    case 'peak':
      return '峰值';
    case 'low_shelf':
      return '低架';
    case 'high_shelf':
      return '高架';
    case 'low_pass':
      return '低通';
    case 'high_pass':
      return '高通';
    case 'notch':
      return '陷波';
    case 'band_pass':
      return '带通';
    case 'all_pass':
      return '全通';
    default:
      return type;
  }
}

class EqBand {
  double freq;
  double gain;
  double q;
  String type;

  /// null = 双声道；0 = 左；1 = 右。
  int? channel;

  EqBand({
    required this.freq,
    required this.gain,
    required this.q,
    required this.type,
    this.channel,
  });

  factory EqBand.fromJson(Map<String, dynamic> j) => EqBand(
        freq: (j['freq'] as num?)?.toDouble() ?? 1000,
        gain: (j['gain'] as num?)?.toDouble() ?? 0,
        q: (j['q'] as num?)?.toDouble() ?? 1,
        type: (j['type'] ?? 'peak') as String,
        channel: (j['channel'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'freq': freq,
        'gain': gain,
        'q': q,
        'type': type,
        'channel': channel,
      };

  EqBand clone() =>
      EqBand(freq: freq, gain: gain, q: q, type: type, channel: channel);
}

class EqProfile {
  bool enabled;
  double? preampDb;

  /// safe = 按最大频响自动预留；manual = 用 preamp_db。
  String headroom;
  List<EqBand> bands;
  double? autoeqPreampDb;

  /// manual / autoeq / geq
  String? source;

  EqProfile({
    this.enabled = false,
    this.preampDb,
    this.headroom = 'safe',
    List<EqBand>? bands,
    this.autoeqPreampDb,
    this.source,
  }) : bands = bands ?? [];

  factory EqProfile.fromJson(Map<String, dynamic> j) => EqProfile(
        enabled: (j['enabled'] as bool?) ?? false,
        preampDb: (j['preamp_db'] as num?)?.toDouble(),
        headroom: (j['headroom'] ?? 'safe') as String,
        bands: (j['bands'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EqBand.fromJson)
            .toList(),
        autoeqPreampDb: (j['autoeq_preamp_db'] as num?)?.toDouble(),
        source: j['source'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preamp_db': preampDb,
        'headroom': headroom,
        'bands': bands.map((b) => b.toJson()).toList(),
        'autoeq_preamp_db': autoeqPreampDb,
        'source': source,
      };
}

class EqState {
  final EqProfile profile;
  final double appliedPreampDb;
  final int effectiveBands;
  final bool isActive;

  EqState({
    required this.profile,
    required this.appliedPreampDb,
    required this.effectiveBands,
    required this.isActive,
  });

  factory EqState.fromJson(Map<String, dynamic> j) => EqState(
        profile: EqProfile.fromJson(
            (j['profile'] as Map<String, dynamic>?) ?? const {}),
        appliedPreampDb: (j['applied_preamp_db'] as num?)?.toDouble() ?? 0,
        effectiveBands: (j['effective_bands'] as num?)?.toInt() ?? 0,
        isActive: (j['is_active'] as bool?) ?? false,
      );
}

class EqResponsePoint {
  final double freq;
  final double db;
  EqResponsePoint({required this.freq, required this.db});
  factory EqResponsePoint.fromJson(Map<String, dynamic> j) => EqResponsePoint(
        freq: (j['freq'] as num?)?.toDouble() ?? 0,
        db: (j['db'] as num?)?.toDouble() ?? 0,
      );
}

class EqResponse {
  final List<EqResponsePoint> points;
  final double appliedPreampDb;
  EqResponse({required this.points, required this.appliedPreampDb});
  factory EqResponse.fromJson(Map<String, dynamic> j) => EqResponse(
        points: (j['points'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EqResponsePoint.fromJson)
            .toList(),
        appliedPreampDb: (j['applied_preamp_db'] as num?)?.toDouble() ?? 0,
      );
}

class GeqPresetInfo {
  final String name;
  final int bands;
  final List<double> gainsDb;
  GeqPresetInfo(
      {required this.name, required this.bands, required this.gainsDb});
  factory GeqPresetInfo.fromJson(Map<String, dynamic> j) => GeqPresetInfo(
        name: (j['name'] ?? '') as String,
        bands: (j['bands'] as num?)?.toInt() ?? 0,
        gainsDb: (j['gains_db'] as List? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class GeqMeta {
  final List<int> bandChoices;
  final List<GeqPresetInfo> presets;
  GeqMeta({required this.bandChoices, required this.presets});
  factory GeqMeta.fromJson(Map<String, dynamic> j) => GeqMeta(
        bandChoices: (j['band_choices'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        presets: (j['presets'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(GeqPresetInfo.fromJson)
            .toList(),
      );
}

class GeqGrid {
  final int bands;
  final List<double> freqs;
  GeqGrid({required this.bands, required this.freqs});
  factory GeqGrid.fromJson(Map<String, dynamic> j) => GeqGrid(
        bands: (j['bands'] as num?)?.toInt() ?? 0,
        freqs: (j['freqs'] as List? ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class AutoEqResult {
  final bool ok;
  final String? name;
  final int bandCount;
  final double? preampDb;
  final double reservedHeadroomDb;
  final bool preampApplied;
  final bool preampCoveredByHeadroom;
  final int ignoredCount;
  final EqProfile? profile;

  AutoEqResult({
    required this.ok,
    this.name,
    required this.bandCount,
    this.preampDb,
    required this.reservedHeadroomDb,
    required this.preampApplied,
    required this.preampCoveredByHeadroom,
    required this.ignoredCount,
    this.profile,
  });

  factory AutoEqResult.fromJson(Map<String, dynamic> j) => AutoEqResult(
        ok: (j['ok'] as bool?) ?? false,
        name: j['name'] as String?,
        bandCount: (j['band_count'] as num?)?.toInt() ?? 0,
        preampDb: (j['preamp_db'] as num?)?.toDouble(),
        reservedHeadroomDb:
            (j['reserved_headroom_db'] as num?)?.toDouble() ?? 0,
        preampApplied: (j['preamp_applied'] as bool?) ?? false,
        preampCoveredByHeadroom:
            (j['preamp_covered_by_headroom'] as bool?) ?? false,
        ignoredCount: (j['ignored_filters'] as List? ?? const []).length,
        profile: j['profile'] == null
            ? null
            : EqProfile.fromJson(j['profile'] as Map<String, dynamic>),
      );
}

/// 智能淡入淡出（毫秒，0 = 关闭；上限 8000）。
class FadeSettings {
  final int fadeInMs;
  final int fadeOutMs;
  FadeSettings({required this.fadeInMs, required this.fadeOutMs});
  factory FadeSettings.fromJson(Map<String, dynamic> j) => FadeSettings(
        fadeInMs: (j['fade_in_ms'] as num?)?.toInt() ?? 0,
        fadeOutMs: (j['fade_out_ms'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toJson() => {
        'fade_in_ms': fadeInMs,
        'fade_out_ms': fadeOutMs,
      };
}

// ---------- ReplayGain ----------

class ReplayGainStatus {
  final int pending;
  final int tagged;
  final int analyzed;
  final int total;
  ReplayGainStatus({
    required this.pending,
    required this.tagged,
    required this.analyzed,
    required this.total,
  });
  factory ReplayGainStatus.fromJson(Map<String, dynamic> j) => ReplayGainStatus(
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        tagged: (j['tagged'] as num?)?.toInt() ?? 0,
        analyzed: (j['analyzed'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

class TrackAnalysis {
  final int songId;
  final String title;
  final bool measured;
  final double? lufs;
  final double? gainDb;
  final double? peak;
  final double? truePeak;
  final String note;
  TrackAnalysis({
    required this.songId,
    required this.title,
    required this.measured,
    this.lufs,
    this.gainDb,
    this.peak,
    this.truePeak,
    required this.note,
  });
  factory TrackAnalysis.fromJson(Map<String, dynamic> j) => TrackAnalysis(
        songId: (j['song_id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '') as String,
        measured: (j['measured'] as bool?) ?? false,
        lufs: (j['lufs'] as num?)?.toDouble(),
        gainDb: (j['gain_db'] as num?)?.toDouble(),
        peak: (j['peak'] as num?)?.toDouble(),
        truePeak: (j['true_peak'] as num?)?.toDouble(),
        note: (j['note'] ?? '') as String,
      );
}

class AnalysisSummary {
  final int scanned;
  final int measured;
  final int skipped;
  final int failed;
  final int filled;
  final int overwritten;
  final int albumsUpdated;
  AnalysisSummary({
    required this.scanned,
    required this.measured,
    required this.skipped,
    required this.failed,
    required this.filled,
    required this.overwritten,
    required this.albumsUpdated,
  });
  factory AnalysisSummary.fromJson(Map<String, dynamic> j) => AnalysisSummary(
        scanned: (j['scanned'] as num?)?.toInt() ?? 0,
        measured: (j['measured'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        filled: (j['filled'] as num?)?.toInt() ?? 0,
        overwritten: (j['overwritten'] as num?)?.toInt() ?? 0,
        albumsUpdated: (j['albums_updated'] as num?)?.toInt() ?? 0,
      );
}

// ---------- 音质档位映射（5 档，与 Web 稿同源） ----------

/// 无损档（cd / hd）在流地址上统一映射为 `quality=lossless`。
String qualityStreamParam(String q) =>
    (q == 'cd' || q == 'hd') ? 'lossless' : q;

/// cd / hd 需要额外带 `bit_depth`；其余档返回 null。
String? qualityBitDepth(String q) =>
    q == 'cd' ? 'cd' : (q == 'hd' ? 'hd' : null);

// ---------- 曲库扫描 / 维护 ----------

/// 一次扫描的统计结果。
class ScanStats {
  final int scanned;
  final int added;
  final int updated;
  final int skipped;
  final int failed;
  final int removed;
  ScanStats({
    required this.scanned,
    required this.added,
    required this.updated,
    required this.skipped,
    required this.failed,
    required this.removed,
  });
  factory ScanStats.fromJson(Map<String, dynamic> j) => ScanStats(
        scanned: (j['scanned'] as num?)?.toInt() ?? 0,
        added: (j['added'] as num?)?.toInt() ?? 0,
        updated: (j['updated'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        removed: (j['removed'] as num?)?.toInt() ?? 0,
      );
}

/// 扫描运行状态与上次结果。
class ScanStatus {
  final bool running;
  final int progress;
  final ScanStats? last;
  final String? lastScanAt;
  final String? message;
  ScanStatus({
    required this.running,
    required this.progress,
    this.last,
    this.lastScanAt,
    this.message,
  });
  factory ScanStatus.fromJson(Map<String, dynamic> j) => ScanStatus(
        running: (j['running'] as bool?) ?? false,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        last: j['last'] == null
            ? null
            : ScanStats.fromJson((j['last'] as Map).cast<String, dynamic>()),
        lastScanAt: j['last_scan_at'] as String?,
        message: j['message'] as String?,
      );
}

/// 扫描目录。
class ScanRoot {
  final int id;
  final String path;
  final bool enabled;
  final String createdAt;
  ScanRoot({
    required this.id,
    required this.path,
    required this.enabled,
    required this.createdAt,
  });
  factory ScanRoot.fromJson(Map<String, dynamic> j) => ScanRoot(
        id: (j['id'] as num?)?.toInt() ?? 0,
        path: (j['path'] ?? '') as String,
        enabled: (j['enabled'] as bool?) ?? true,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

// ---------- 系统配置 ----------

class ConfigItem {
  final String key;
  final String value;
  final String? description;
  ConfigItem({required this.key, required this.value, this.description});
  factory ConfigItem.fromJson(Map<String, dynamic> j) => ConfigItem(
        key: (j['key'] ?? '') as String,
        value: (j['value'] ?? '') as String,
        description: j['description'] as String?,
      );
}

class SystemConfig {
  final List<ConfigItem> items;
  final bool enableWriteAudioTags;
  final bool softMute;
  final bool autoPlayNext;
  final bool syncEnabled;
  final int maxDspJobs;
  SystemConfig({
    required this.items,
    required this.enableWriteAudioTags,
    required this.softMute,
    required this.autoPlayNext,
    required this.syncEnabled,
    required this.maxDspJobs,
  });
  factory SystemConfig.fromJson(Map<String, dynamic> j) => SystemConfig(
        items: ((j['items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ConfigItem.fromJson)
            .toList(),
        enableWriteAudioTags: (j['enable_write_audio_tags'] as bool?) ?? false,
        softMute: (j['soft_mute'] as bool?) ?? true,
        autoPlayNext: (j['auto_play_next'] as bool?) ?? true,
        syncEnabled: (j['sync_enabled'] as bool?) ?? true,
        maxDspJobs: (j['max_dsp_jobs'] as num?)?.toInt() ?? 2,
      );
}

class ScrapeResult {
  final int songId;
  final bool found;
  final bool updatedArtist;
  final bool updatedAlbum;
  final bool gotLyrics;
  final bool gotCover;
  final List<String> sources;

  ScrapeResult({
    required this.songId,
    required this.found,
    required this.updatedArtist,
    required this.updatedAlbum,
    required this.gotLyrics,
    required this.gotCover,
    required this.sources,
  });

  factory ScrapeResult.fromJson(Map<String, dynamic> j) => ScrapeResult(
        songId: (j['song_id'] as num?)?.toInt() ?? 0,
        found: (j['found'] as bool?) ?? false,
        updatedArtist: (j['updated_artist'] as bool?) ?? false,
        updatedAlbum: (j['updated_album'] as bool?) ?? false,
        gotLyrics: (j['got_lyrics'] as bool?) ?? false,
        gotCover: (j['got_cover'] as bool?) ?? false,
        sources: (j['sources'] as List? ?? const []).map((e) => '$e').toList(),
      );
}

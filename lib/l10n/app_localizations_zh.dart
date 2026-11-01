// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'FN Audio';

  @override
  String get tabHome => '首页';

  @override
  String get tabClips => '片段';

  @override
  String get tabLibrary => '曲库';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonClose => '关闭';

  @override
  String get commonRetry => '重试';

  @override
  String get meTitle => '我的';

  @override
  String get meGuest => '未登录';

  @override
  String get meAccountAdmin => '管理员';

  @override
  String get meAccountLocal => '本地曲库';

  @override
  String get groupAudio => '音频';

  @override
  String get groupPlaybackLibrary => '播放与曲库';

  @override
  String get groupSystem => '系统';

  @override
  String get groupPlayback => '播放';

  @override
  String get meEqEffects => '均衡器与音效';

  @override
  String get meEqDefault => '原声';

  @override
  String get meEqEnabled => '已启用';

  @override
  String get meQualityTier => '音质档位';

  @override
  String get rgModeTitle => 'ReplayGain 模式';

  @override
  String get rgOff => '关闭';

  @override
  String get rgTrack => '按音轨';

  @override
  String get rgAlbum => '按专辑';

  @override
  String get meFade => '淡入淡出';

  @override
  String fadeSeconds(String seconds) {
    return '$seconds 秒';
  }

  @override
  String get meDevice => '播放设备';

  @override
  String get meDeviceLocal => '本机扬声器';

  @override
  String get meSignalPath => '信号路径';

  @override
  String get meScanLibrary => '扫描曲库';

  @override
  String get scanLoading => '加载中…';

  @override
  String scanProgress(int percent) {
    return '扫描中 $percent%';
  }

  @override
  String get scanIdle => '空闲';

  @override
  String get theme => '主题';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get logout => '退出登录';

  @override
  String get logoutConfirmTitle => '退出登录';

  @override
  String get logoutConfirmBody => '确定退出当前账号？';

  @override
  String get logoutAction => '退出';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingSoftMute => '暂停软静音';

  @override
  String get settingAutoPlayNext => '自动播放下一首';

  @override
  String get settingSyncEnabled => '多端播放状态同步';

  @override
  String get settingBackendUrl => '后端地址';

  @override
  String get settingDspJobs => '转码并发数';

  @override
  String get serverAddressTitle => '服务器地址';

  @override
  String get serverAddressHint => '修改后需重新登录（旧会话对新服务器无效）';

  @override
  String get serverSaveAndRelogin => '保存并重登';

  @override
  String get language => '语言';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageSystem => '跟随系统';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get playerNoSong => '未选择歌曲';

  @override
  String playbackFailed(String error) {
    return '播放失败：$error';
  }

  @override
  String playerOpFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String castingTo(String name) {
    return '正在投屏到 $name';
  }

  @override
  String get playerFx => '音效';

  @override
  String get playerEqReplayGain => '均衡器预设 · ReplayGain';

  @override
  String get playerPassthrough => '原声直通';

  @override
  String get more => '更多';

  @override
  String moreQueueSummary(int count, String artist) {
    return '$count 首待播 · $artist';
  }

  @override
  String get moreUpNext => '接下来';

  @override
  String get moreQueue => '播放队列';

  @override
  String get moreLyrics => '歌词';

  @override
  String get moreLyricsSub => '逐行同步';

  @override
  String get moreRelated => '相关';

  @override
  String get moreRelatedSub => '艺人 · 专辑';

  @override
  String get moreSignalPath => '信号路径';

  @override
  String get moreSignalPathSub => '查看完整处理链路';

  @override
  String get moreDevice => '播放设备';

  @override
  String get moreDeviceSub => '本机 / DLNA';

  @override
  String get loadFailed => '加载失败';

  @override
  String get loadFailedTip => '请检查网络连接或后端服务，稍后再试';

  @override
  String loadFailedWith(String error) {
    return '加载失败：$error';
  }

  @override
  String get noHistory => '还没有播放记录';

  @override
  String get homeTitle => '首页';

  @override
  String get recentPlayed => '最近播放';

  @override
  String get continueListening => '继续收听';

  @override
  String get clipsTitle => '片段';

  @override
  String get clipsEmpty => '还没有片段';

  @override
  String get clipsUnavailable => '曲库服务端暂未提供视频片段接口，接入后这里会按现场 / 翻唱 / 已收藏分组展示。';

  @override
  String get filterAll => '全部';

  @override
  String get filterLive => '现场';

  @override
  String get filterCover => '翻唱';

  @override
  String get filterFavorites => '已收藏';

  @override
  String get filterRecent => '最近';

  @override
  String get filterLossy => '有损';

  @override
  String get libraryTitle => '曲库';

  @override
  String get playlistsTitle => '歌单';

  @override
  String get allSongs => '全部歌曲';

  @override
  String songCount(int count) {
    return '$count 首';
  }

  @override
  String get noPlaylists => '还没有歌单，点右上角 + 新建';

  @override
  String get playlistsLoadFailed => '歌单加载失败';

  @override
  String get noMatchedSongs => '没有匹配的歌曲';

  @override
  String get noMatchedAlbums => '没有匹配的专辑';

  @override
  String get noMatchedArtists => '没有匹配的艺人';

  @override
  String get noMatchedPlaylists => '没有匹配的歌单';

  @override
  String get newPlaylist => '新建歌单';

  @override
  String get playlistName => '歌单名称';

  @override
  String get create => '创建';

  @override
  String createFailed(String error) {
    return '创建失败：$error';
  }

  @override
  String playlistSongCount(int count) {
    return '歌单 · $count 首';
  }

  @override
  String artistSongCount(String artist, int count) {
    return '$artist · $count 首';
  }

  @override
  String get queueEmpty => '播放队列为空';

  @override
  String get searchSongs => '歌曲';

  @override
  String get searchAlbums => '专辑';

  @override
  String get searchArtists => '艺人';

  @override
  String get searchPlaylists => '歌单';

  @override
  String get searchHint => '歌曲、专辑、艺人';

  @override
  String get searchStart => '输入关键词开始搜索';

  @override
  String searchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String get historyTitle => '收听历史';

  @override
  String get tuningTitle => '调音';

  @override
  String get tuningEqualizer => '均衡器';

  @override
  String tuningToggleFailed(String error) {
    return '切换失败：$error';
  }

  @override
  String get tuningEqCleared => '已清除均衡器';

  @override
  String tuningEqClearFailed(String error) {
    return '清除失败：$error';
  }

  @override
  String tuningApplyFailed(String error) {
    return '应用失败：$error';
  }

  @override
  String get tuningPeqApplied => 'PEQ 已应用';

  @override
  String get tuningClear => '清除';

  @override
  String get tuningFadeIn => '淡入';

  @override
  String get tuningFadeOut => '淡出';

  @override
  String get tuningFadesSaved => '淡入淡出已保存';

  @override
  String tuningBandCount(int count) {
    return '$count 段';
  }

  @override
  String get tuningPresetLabel => '预设';

  @override
  String get tuningPresets => '音效预设';

  @override
  String get tuningPresetNone => '原声（无音效）';

  @override
  String get tuningPresetSystem => '系统';

  @override
  String get tuningAddBand => '添加频段';

  @override
  String get tuningApply => '应用';

  @override
  String get tuningBandType => '频段类型';

  @override
  String get tuningAutoeqHint =>
      '粘贴 AutoEq 参数文本，例如：\nPreamp: -6.2 dB\nFilter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70';

  @override
  String get tuningAutoeqPaste => '请粘贴 AutoEq 参数文本';

  @override
  String get tuningImportApply => '导入并应用';

  @override
  String tuningImportOk(int count) {
    return '已导入 $count 段';
  }

  @override
  String tuningImportOkWithHeadroom(int count, String headroom) {
    return '已导入 $count 段，预留 ${headroom}dB headroom';
  }

  @override
  String get tuningImportNotOk => '导入未成功';

  @override
  String tuningImportError(String error) {
    return '导入失败：$error';
  }

  @override
  String get tuningDeletePresetTitle => '删除预设';

  @override
  String tuningDeletePresetBody(String name) {
    return '确定删除「$name」？';
  }

  @override
  String get tuningDelete => '删除';

  @override
  String tuningDeleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get commonOk => '确定';

  @override
  String get commonRemove => '移除';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get lossy => '有损';

  @override
  String get myMusic => '我的音乐';

  @override
  String get favorites => '收藏';

  @override
  String get noFavorites => '暂无收藏';

  @override
  String get noPlayHistory => '暂无播放历史';

  @override
  String get noPlaylistsHint => '还没有歌单，点击右上角新建';

  @override
  String get deletePlaylist => '删除歌单';

  @override
  String deletePlaylistBody(String name) {
    return '确定删除「$name」？';
  }

  @override
  String get playAll => '播放全部';

  @override
  String get addSongs => '加入歌曲';

  @override
  String get noPlaylistSongs => '这个歌单还没有歌曲';

  @override
  String get noPlaylistSongsHint => '点右上角 + 号，从收藏或最近播放里挑几首';

  @override
  String get noSongsToAdd => '暂无可添加的歌曲（先收藏或播放歌曲）';

  @override
  String get scanPageTitle => '扫描与维护';

  @override
  String get scanStatusHeader => '扫描状态';

  @override
  String get scanLibrary => '曲库扫描';

  @override
  String get scanProgressLabel => '扫描进度';

  @override
  String get scanLastDone => '上次完成';

  @override
  String get scanLastStats => '上次统计';

  @override
  String get scanFiles => '扫描文件';

  @override
  String get scanAddedUpdated => '新增 / 更新';

  @override
  String get scanRemoved => '清理失效';

  @override
  String get scanSkipped => '跳过';

  @override
  String get scanFailedCount => '失败';

  @override
  String get scanStart => '开始扫描';

  @override
  String get scanFullRescan => '全量重扫';

  @override
  String get scanRootsHeader => '扫描目录';

  @override
  String get scanRootsHint => '只扫描这些根目录；移除目录仅停止扫描，已入库记录保留。';

  @override
  String get scanNoRoots => '暂无扫描目录';

  @override
  String get scanRootEnabled => '启用中';

  @override
  String get scanRootDisabled => '已停用';

  @override
  String get scanAddDir => '添加目录';

  @override
  String get scanAddRootTitle => '添加扫描目录';

  @override
  String get scanRootPath => '目录路径';

  @override
  String get scanRemoveRootTitle => '移除扫描目录';

  @override
  String scanRemoveRootBody(String path) {
    return '确定移除「$path」？\n仅停止扫描该目录，已入库记录保留。';
  }

  @override
  String scanStatusLoadFailed(String error) {
    return '状态加载失败：$error';
  }

  @override
  String scanRunning(int progress) {
    return '进行中 $progress%';
  }

  @override
  String get scanStartedFull => '已开始全量重扫';

  @override
  String get scanStartedIncremental => '已开始增量扫描';

  @override
  String scanTriggerFailed(String error) {
    return '触发失败：$error';
  }

  @override
  String get scanRootAdded => '已添加目录';

  @override
  String scanRootAddFailed(String error) {
    return '添加失败：$error';
  }

  @override
  String get scanRootRemoved => '已移除目录';

  @override
  String scanRootRemoveFailed(String error) {
    return '移除失败：$error';
  }

  @override
  String get devicesTitle => '输出设备';

  @override
  String get rescan => '重新扫描';

  @override
  String get availableDevices => '可用设备';

  @override
  String get deviceLocal => '本机';

  @override
  String get clientAudioOut => '客户端音频输出';

  @override
  String scanFailed(String error) {
    return '扫描失败：$error';
  }

  @override
  String get noDlnaRenderers => '未发现 DLNA 渲染器';

  @override
  String get outputParams => '输出参数';

  @override
  String get deviceLabel => '设备';

  @override
  String get sampleRatePolicy => '采样率策略';

  @override
  String get followSource => '跟随源';

  @override
  String get dsdPassThrough => 'DSD 原样送接收端';

  @override
  String get dsdExtractPoint => 'DSD 抽取落点';

  @override
  String get eqFade => 'EQ / 淡入淡出';

  @override
  String get bypass => '旁路';

  @override
  String nowPlayingLabel(String song) {
    return '正在播放：$song';
  }

  @override
  String get selectSongFirst => '请先选择一首歌曲';

  @override
  String castSuccess(String name) {
    return '已投屏到 $name';
  }

  @override
  String castFailed(String error) {
    return '投屏失败：$error';
  }

  @override
  String get backToLocal => '已切回本机播放';

  @override
  String get loginSubtitle => '飞牛 NAS 私有化 HIFI 流媒体';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get restoreDefault => '恢复默认地址';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get login => '登录';

  @override
  String get serverUrlEmpty => '地址不能为空';

  @override
  String get serverUrlScheme => '地址必须以 http:// 或 https:// 开头';

  @override
  String get serverUrlHost => '地址缺少主机名或 IP';

  @override
  String serverInvalid(String error) {
    return '服务器地址有误：$error';
  }

  @override
  String loginFailed(String error) {
    return '登录失败：$error';
  }

  @override
  String get qualityTierTitle => '音质档位';

  @override
  String get qualityLossless => '无损 · 跟随源';

  @override
  String get qualityCd => '无损 · 16 bit';

  @override
  String get qualityHd => '无损 · 24 bit';

  @override
  String get playNext => '下一首播放';

  @override
  String get addedToPlayNext => '已加入下一首播放';

  @override
  String get addToPlaylist => '添加到歌单';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get favorite => '收藏';

  @override
  String opFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String get lyricsEdit => '歌词查看 / 编辑';

  @override
  String get scrapeMetadata => '联网刮削元数据';

  @override
  String scrapeDone(String lyrics, String cover) {
    return '刮削完成：歌词 $lyrics 封面 $cover';
  }

  @override
  String get noOnlineMatch => '未找到在线匹配结果';

  @override
  String scrapeFailed(String error) {
    return '刮削失败：$error';
  }

  @override
  String get addedToPlaylist => '已加入歌单';

  @override
  String addToPlaylistFailed(String error) {
    return '加入失败：$error';
  }

  @override
  String get chooseDevice => '选择播放设备';

  @override
  String get localPlayback => '本机播放';

  @override
  String get dlnaRenderer => 'DLNA 渲染器';

  @override
  String castedTo(String name) {
    return '已投屏：$name';
  }

  @override
  String get signalPathTitle => '信号路径';

  @override
  String get notPlaying => '未在播放';

  @override
  String get rgNotEnabled => '未启用';

  @override
  String get rgMissingTag => '该文件缺少标签，未调整';

  @override
  String rgLinearGain(String gain) {
    return '线性增益 ${gain}x';
  }

  @override
  String get rgPeakCap => '峰值封顶防削波';

  @override
  String get dlnaPush => 'DLNA 推送';

  @override
  String get rendererFallback => '渲染器';

  @override
  String get flacFollowSource => 'FLAC 跟随源';

  @override
  String get httpStream => 'HTTP 音频流（服务端整段处理）';

  @override
  String outParams(String label) {
    return '$label · 48kHz 立体声';
  }

  @override
  String get httpDirect => 'HTTP 直出（原始文件）';

  @override
  String get httpDirectSub => '字节流 Range 寻址 · 服务端不处理';

  @override
  String get sourceFile => '源文件';

  @override
  String decodeToPcm(String codec) {
    return '解码 $codec → PCM';
  }

  @override
  String get symphoniaDecode => 'symphonia 服务端解码';

  @override
  String get resampleMix => '重采样 / 混音';

  @override
  String resampleTarget(String source) {
    return '$source → 48kHz · 立体声';
  }

  @override
  String get resamplePassthrough => '直通，保持原始格式';

  @override
  String presetWithName(String name) {
    return '音效预设 · $name';
  }

  @override
  String get camillaDsp => 'camilladsp DSP 链路处理';

  @override
  String get presetIdle => '未启用 · 原声直通';

  @override
  String get volumeMuted => '音量 · 已静音';

  @override
  String volumePercent(int percent) {
    return '音量 $percent%';
  }

  @override
  String get clientVolume => '客户端本地音量';

  @override
  String get dlnaRendererOutput => 'DLNA 渲染器输出';

  @override
  String get lyricsLoadFailed => '歌词加载失败';

  @override
  String get noLyrics => '暂无歌词';

  @override
  String get noLyricsHint => '可在 Web 端编辑或上传 LRC 文件';

  @override
  String get levelMeter => '电平';

  @override
  String get relatedTitle => '相关';

  @override
  String get relatedArtists => '相关艺人';

  @override
  String get noSameArtist => '曲库里暂无同艺人作品';

  @override
  String get relatedAlbums => '相关专辑';

  @override
  String get noSameAlbum => '曲库里暂无同专辑作品';

  @override
  String get youMayLike => '你可能也喜欢';

  @override
  String get noRecommendations => '暂无推荐';

  @override
  String get lyrics => '歌词';

  @override
  String lyricsWithTitle(String title) {
    return '歌词 · $title';
  }

  @override
  String get uploadLrc => '上传 LRC';

  @override
  String get lyricsSaved => '歌词已保存（来源：手动编辑）';

  @override
  String uploadSuccess(String name) {
    return '上传成功：$name';
  }

  @override
  String uploadFailed(String error) {
    return '上传失败：$error';
  }

  @override
  String get lyricsEmptyHint => '暂无歌词，可点击「编辑」或「上传 LRC」';

  @override
  String get lyricsPlaceholder => '[00:00.00]第一行歌词\n[00:03.00]第二行歌词';

  @override
  String get lyricSourceUser => '手动编辑';

  @override
  String get lyricSourceEmbedded => '音频内嵌';

  @override
  String get lyricSourceFile => 'LRC 文件';

  @override
  String get lyricSourceNetwork => '网络刮削';

  @override
  String get lyricSourceNone => '无歌词';

  @override
  String rgAnalyzeDone(int measured, int skipped, int failed) {
    return '分析完成：实测 $measured · 跳过 $skipped · 失败 $failed';
  }

  @override
  String rgAnalyzeFailed(String error) {
    return '分析失败：$error';
  }

  @override
  String get rgMeasureHeader => '实测口径';

  @override
  String get rgKWeighting => 'K 计权 + 400ms / 100ms 分块 + 双重门限';

  @override
  String get rgTruePeak => '真峰值（附录 2）参与防削波';

  @override
  String get rgImplemented => '已实现';

  @override
  String get rgByChannelLayout => '按源声道布局测量';

  @override
  String get rgCorrect => '正确';

  @override
  String get rgAlbumGainWeighted => '专辑增益按时长加权能量合成';

  @override
  String get rgAnalyzeMissing => '分析缺失曲目';

  @override
  String get rgReanalyzeAll => '全部重新分析';

  @override
  String rgStatusLoadFailed(String error) {
    return '状态加载失败：$error';
  }

  @override
  String get rgRefLevel => '参考电平 LUFS';

  @override
  String get rgAnalyzedCount => '首已实测';

  @override
  String get rgPendingCount => '首待分析';

  @override
  String get rgTaggedCount => '标签曲目';

  @override
  String get libTabSongs => '歌曲';

  @override
  String get libTabAlbums => '专辑';

  @override
  String get libTabArtists => '歌手';

  @override
  String get libTabGenres => '风格';

  @override
  String get albumsTitle => '专辑';

  @override
  String get artistsTitle => '歌手';

  @override
  String get genresTitle => '风格';

  @override
  String get noAlbums => '暂无专辑';

  @override
  String get noArtists => '暂无歌手';

  @override
  String get noGenres => '暂无风格';

  @override
  String get unknownArtist => '未知艺术家';

  @override
  String get unknownYear => '未知年份';

  @override
  String get unknownGenre => '未知风格';

  @override
  String get followArtist => '关注';

  @override
  String get followingArtist => '已关注';

  @override
  String followFailed(String error) {
    return '操作失败：$error';
  }

  @override
  String itemCount(int count) {
    return '$count 个';
  }

  @override
  String albumCount(int count) {
    return '$count 张专辑';
  }

  @override
  String get followedArtists => '关注歌手';

  @override
  String get dailyRecommendations => '每日推荐';

  @override
  String get refreshRecommendations => '换一批';

  @override
  String get recommendationEmpty => '暂无推荐，先去收藏或播放一些歌曲';

  @override
  String get roamTitle => '漫游';

  @override
  String get roamSimilar => '相似漫游';

  @override
  String get roamTaste => '口味漫游';

  @override
  String get roamRandom => '随机漫游';

  @override
  String get roamStop => '结束漫游';

  @override
  String get roamHint => '按相似、口味或随机持续播放，播到队尾自动续接';

  @override
  String get setPlaylistCover => '设为封面';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';
}

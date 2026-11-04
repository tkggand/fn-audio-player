import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'FN Audio'**
  String get appTitle;

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get tabHome;

  /// No description provided for @tabClips.
  ///
  /// In zh, this message translates to:
  /// **'片段'**
  String get tabClips;

  /// No description provided for @tabLibrary.
  ///
  /// In zh, this message translates to:
  /// **'曲库'**
  String get tabLibrary;

  /// No description provided for @commonCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get commonRetry;

  /// No description provided for @meTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get meTitle;

  /// No description provided for @meGuest.
  ///
  /// In zh, this message translates to:
  /// **'未登录'**
  String get meGuest;

  /// No description provided for @meAccountAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get meAccountAdmin;

  /// No description provided for @meAccountLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地曲库'**
  String get meAccountLocal;

  /// No description provided for @groupAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get groupAudio;

  /// No description provided for @groupPlaybackLibrary.
  ///
  /// In zh, this message translates to:
  /// **'播放与曲库'**
  String get groupPlaybackLibrary;

  /// No description provided for @groupSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get groupSystem;

  /// No description provided for @groupPlayback.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get groupPlayback;

  /// No description provided for @meEqEffects.
  ///
  /// In zh, this message translates to:
  /// **'均衡器与音效'**
  String get meEqEffects;

  /// No description provided for @meEqDefault.
  ///
  /// In zh, this message translates to:
  /// **'原声'**
  String get meEqDefault;

  /// No description provided for @meEqEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get meEqEnabled;

  /// No description provided for @meQualityTier.
  ///
  /// In zh, this message translates to:
  /// **'音质档位'**
  String get meQualityTier;

  /// No description provided for @rgModeTitle.
  ///
  /// In zh, this message translates to:
  /// **'ReplayGain 模式'**
  String get rgModeTitle;

  /// No description provided for @rgOff.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get rgOff;

  /// No description provided for @rgTrack.
  ///
  /// In zh, this message translates to:
  /// **'按音轨'**
  String get rgTrack;

  /// No description provided for @rgAlbum.
  ///
  /// In zh, this message translates to:
  /// **'按专辑'**
  String get rgAlbum;

  /// No description provided for @meFade.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出'**
  String get meFade;

  /// No description provided for @fadeSeconds.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒'**
  String fadeSeconds(String seconds);

  /// No description provided for @meDevice.
  ///
  /// In zh, this message translates to:
  /// **'播放设备'**
  String get meDevice;

  /// No description provided for @meDeviceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本机扬声器'**
  String get meDeviceLocal;

  /// No description provided for @meSignalPath.
  ///
  /// In zh, this message translates to:
  /// **'信号路径'**
  String get meSignalPath;

  /// No description provided for @meScanLibrary.
  ///
  /// In zh, this message translates to:
  /// **'扫描曲库'**
  String get meScanLibrary;

  /// No description provided for @scanLoading.
  ///
  /// In zh, this message translates to:
  /// **'加载中…'**
  String get scanLoading;

  /// No description provided for @scanProgress.
  ///
  /// In zh, this message translates to:
  /// **'扫描中 {percent}%'**
  String scanProgress(int percent);

  /// No description provided for @scanIdle.
  ///
  /// In zh, this message translates to:
  /// **'空闲'**
  String get scanIdle;

  /// No description provided for @theme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'确定退出当前账号？'**
  String get logoutConfirmBody;

  /// No description provided for @logoutAction.
  ///
  /// In zh, this message translates to:
  /// **'退出'**
  String get logoutAction;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingSoftMute.
  ///
  /// In zh, this message translates to:
  /// **'暂停软静音'**
  String get settingSoftMute;

  /// No description provided for @settingAutoPlayNext.
  ///
  /// In zh, this message translates to:
  /// **'自动播放下一首'**
  String get settingAutoPlayNext;

  /// No description provided for @settingSyncEnabled.
  ///
  /// In zh, this message translates to:
  /// **'多端播放状态同步'**
  String get settingSyncEnabled;

  /// No description provided for @settingBackendUrl.
  ///
  /// In zh, this message translates to:
  /// **'后端地址'**
  String get settingBackendUrl;

  /// No description provided for @settingDspJobs.
  ///
  /// In zh, this message translates to:
  /// **'转码并发数'**
  String get settingDspJobs;

  /// No description provided for @serverAddressTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddressTitle;

  /// No description provided for @serverAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'修改后需重新登录（旧会话对新服务器无效）'**
  String get serverAddressHint;

  /// No description provided for @serverSaveAndRelogin.
  ///
  /// In zh, this message translates to:
  /// **'保存并重登'**
  String get serverSaveAndRelogin;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String saveFailed(String error);

  /// No description provided for @playerNoSong.
  ///
  /// In zh, this message translates to:
  /// **'未选择歌曲'**
  String get playerNoSong;

  /// No description provided for @playbackFailed.
  ///
  /// In zh, this message translates to:
  /// **'播放失败：{error}'**
  String playbackFailed(String error);

  /// No description provided for @playerOpFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String playerOpFailed(String error);

  /// No description provided for @castingTo.
  ///
  /// In zh, this message translates to:
  /// **'正在投屏到 {name}'**
  String castingTo(String name);

  /// No description provided for @playerFx.
  ///
  /// In zh, this message translates to:
  /// **'音效'**
  String get playerFx;

  /// No description provided for @playerEqReplayGain.
  ///
  /// In zh, this message translates to:
  /// **'均衡器预设 · ReplayGain'**
  String get playerEqReplayGain;

  /// No description provided for @playerPassthrough.
  ///
  /// In zh, this message translates to:
  /// **'原声直通'**
  String get playerPassthrough;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @moreQueueSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首待播 · {artist}'**
  String moreQueueSummary(int count, String artist);

  /// No description provided for @moreUpNext.
  ///
  /// In zh, this message translates to:
  /// **'接下来'**
  String get moreUpNext;

  /// No description provided for @moreQueue.
  ///
  /// In zh, this message translates to:
  /// **'播放队列'**
  String get moreQueue;

  /// No description provided for @moreLyrics.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get moreLyrics;

  /// No description provided for @moreLyricsSub.
  ///
  /// In zh, this message translates to:
  /// **'逐行同步'**
  String get moreLyricsSub;

  /// No description provided for @moreRelated.
  ///
  /// In zh, this message translates to:
  /// **'相关'**
  String get moreRelated;

  /// No description provided for @moreRelatedSub.
  ///
  /// In zh, this message translates to:
  /// **'艺人 · 专辑'**
  String get moreRelatedSub;

  /// No description provided for @moreSignalPath.
  ///
  /// In zh, this message translates to:
  /// **'信号路径'**
  String get moreSignalPath;

  /// No description provided for @moreSignalPathSub.
  ///
  /// In zh, this message translates to:
  /// **'查看完整处理链路'**
  String get moreSignalPathSub;

  /// No description provided for @moreDevice.
  ///
  /// In zh, this message translates to:
  /// **'播放设备'**
  String get moreDevice;

  /// No description provided for @moreDeviceSub.
  ///
  /// In zh, this message translates to:
  /// **'本机 / DLNA'**
  String get moreDeviceSub;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败'**
  String get loadFailed;

  /// No description provided for @loadFailedTip.
  ///
  /// In zh, this message translates to:
  /// **'请检查网络连接或后端服务，稍后再试'**
  String get loadFailedTip;

  /// No description provided for @loadFailedWith.
  ///
  /// In zh, this message translates to:
  /// **'加载失败：{error}'**
  String loadFailedWith(String error);

  /// No description provided for @noHistory.
  ///
  /// In zh, this message translates to:
  /// **'还没有播放记录'**
  String get noHistory;

  /// No description provided for @homeTitle.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get homeTitle;

  /// No description provided for @recentPlayed.
  ///
  /// In zh, this message translates to:
  /// **'最近播放'**
  String get recentPlayed;

  /// No description provided for @continueListening.
  ///
  /// In zh, this message translates to:
  /// **'继续收听'**
  String get continueListening;

  /// No description provided for @clipsTitle.
  ///
  /// In zh, this message translates to:
  /// **'片段'**
  String get clipsTitle;

  /// No description provided for @clipsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有片段'**
  String get clipsEmpty;

  /// No description provided for @clipsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'曲库服务端暂未提供视频片段接口，接入后这里会按现场 / 翻唱 / 已收藏分组展示。'**
  String get clipsUnavailable;

  /// No description provided for @filterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get filterAll;

  /// No description provided for @filterLive.
  ///
  /// In zh, this message translates to:
  /// **'现场'**
  String get filterLive;

  /// No description provided for @filterCover.
  ///
  /// In zh, this message translates to:
  /// **'翻唱'**
  String get filterCover;

  /// No description provided for @filterFavorites.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get filterFavorites;

  /// No description provided for @filterRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近'**
  String get filterRecent;

  /// No description provided for @filterLossy.
  ///
  /// In zh, this message translates to:
  /// **'有损'**
  String get filterLossy;

  /// No description provided for @libraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'曲库'**
  String get libraryTitle;

  /// No description provided for @playlistsTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get playlistsTitle;

  /// No description provided for @allSongs.
  ///
  /// In zh, this message translates to:
  /// **'全部歌曲'**
  String get allSongs;

  /// No description provided for @songCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 首'**
  String songCount(int count);

  /// No description provided for @noPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'还没有歌单，点右上角 + 新建'**
  String get noPlaylists;

  /// No description provided for @playlistsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'歌单加载失败'**
  String get playlistsLoadFailed;

  /// No description provided for @noMatchedSongs.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的歌曲'**
  String get noMatchedSongs;

  /// No description provided for @noMatchedAlbums.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的专辑'**
  String get noMatchedAlbums;

  /// No description provided for @noMatchedArtists.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的艺人'**
  String get noMatchedArtists;

  /// No description provided for @noMatchedPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的歌单'**
  String get noMatchedPlaylists;

  /// No description provided for @newPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'新建歌单'**
  String get newPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In zh, this message translates to:
  /// **'歌单名称'**
  String get playlistName;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @createFailed.
  ///
  /// In zh, this message translates to:
  /// **'创建失败：{error}'**
  String createFailed(String error);

  /// No description provided for @playlistSongCount.
  ///
  /// In zh, this message translates to:
  /// **'歌单 · {count} 首'**
  String playlistSongCount(int count);

  /// No description provided for @artistSongCount.
  ///
  /// In zh, this message translates to:
  /// **'{artist} · {count} 首'**
  String artistSongCount(String artist, int count);

  /// No description provided for @queueEmpty.
  ///
  /// In zh, this message translates to:
  /// **'播放队列为空'**
  String get queueEmpty;

  /// No description provided for @searchSongs.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get searchSongs;

  /// No description provided for @searchAlbums.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get searchAlbums;

  /// No description provided for @searchArtists.
  ///
  /// In zh, this message translates to:
  /// **'艺人'**
  String get searchArtists;

  /// No description provided for @searchPlaylists.
  ///
  /// In zh, this message translates to:
  /// **'歌单'**
  String get searchPlaylists;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'歌曲、专辑、艺人'**
  String get searchHint;

  /// No description provided for @searchStart.
  ///
  /// In zh, this message translates to:
  /// **'输入关键词开始搜索'**
  String get searchStart;

  /// No description provided for @searchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索失败：{error}'**
  String searchFailed(String error);

  /// No description provided for @historyTitle.
  ///
  /// In zh, this message translates to:
  /// **'收听历史'**
  String get historyTitle;

  /// No description provided for @tuningTitle.
  ///
  /// In zh, this message translates to:
  /// **'调音'**
  String get tuningTitle;

  /// No description provided for @tuningEqualizer.
  ///
  /// In zh, this message translates to:
  /// **'均衡器'**
  String get tuningEqualizer;

  /// No description provided for @tuningToggleFailed.
  ///
  /// In zh, this message translates to:
  /// **'切换失败：{error}'**
  String tuningToggleFailed(String error);

  /// No description provided for @tuningEqCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清除均衡器'**
  String get tuningEqCleared;

  /// No description provided for @tuningEqClearFailed.
  ///
  /// In zh, this message translates to:
  /// **'清除失败：{error}'**
  String tuningEqClearFailed(String error);

  /// No description provided for @tuningApplyFailed.
  ///
  /// In zh, this message translates to:
  /// **'应用失败：{error}'**
  String tuningApplyFailed(String error);

  /// No description provided for @tuningPeqApplied.
  ///
  /// In zh, this message translates to:
  /// **'PEQ 已应用'**
  String get tuningPeqApplied;

  /// No description provided for @tuningClear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get tuningClear;

  /// No description provided for @tuningFadeIn.
  ///
  /// In zh, this message translates to:
  /// **'淡入'**
  String get tuningFadeIn;

  /// No description provided for @tuningFadeOut.
  ///
  /// In zh, this message translates to:
  /// **'淡出'**
  String get tuningFadeOut;

  /// No description provided for @tuningFadesSaved.
  ///
  /// In zh, this message translates to:
  /// **'淡入淡出已保存'**
  String get tuningFadesSaved;

  /// No description provided for @tuningBandCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 段'**
  String tuningBandCount(int count);

  /// No description provided for @tuningPresetLabel.
  ///
  /// In zh, this message translates to:
  /// **'预设'**
  String get tuningPresetLabel;

  /// No description provided for @tuningPresets.
  ///
  /// In zh, this message translates to:
  /// **'音效预设'**
  String get tuningPresets;

  /// No description provided for @tuningPresetNone.
  ///
  /// In zh, this message translates to:
  /// **'原声（无音效）'**
  String get tuningPresetNone;

  /// No description provided for @tuningPresetSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get tuningPresetSystem;

  /// No description provided for @tuningAddBand.
  ///
  /// In zh, this message translates to:
  /// **'添加频段'**
  String get tuningAddBand;

  /// No description provided for @tuningApply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get tuningApply;

  /// No description provided for @tuningBandType.
  ///
  /// In zh, this message translates to:
  /// **'频段类型'**
  String get tuningBandType;

  /// No description provided for @tuningAutoeqHint.
  ///
  /// In zh, this message translates to:
  /// **'粘贴 AutoEq 参数文本，例如：\nPreamp: -6.2 dB\nFilter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70'**
  String get tuningAutoeqHint;

  /// No description provided for @tuningAutoeqPaste.
  ///
  /// In zh, this message translates to:
  /// **'请粘贴 AutoEq 参数文本'**
  String get tuningAutoeqPaste;

  /// No description provided for @tuningImportApply.
  ///
  /// In zh, this message translates to:
  /// **'导入并应用'**
  String get tuningImportApply;

  /// No description provided for @tuningImportOk.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {count} 段'**
  String tuningImportOk(int count);

  /// No description provided for @tuningImportOkWithHeadroom.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {count} 段，预留 {headroom}dB headroom'**
  String tuningImportOkWithHeadroom(int count, String headroom);

  /// No description provided for @tuningImportNotOk.
  ///
  /// In zh, this message translates to:
  /// **'导入未成功'**
  String get tuningImportNotOk;

  /// No description provided for @tuningImportError.
  ///
  /// In zh, this message translates to:
  /// **'导入失败：{error}'**
  String tuningImportError(String error);

  /// No description provided for @tuningDeletePresetTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除预设'**
  String get tuningDeletePresetTitle;

  /// No description provided for @tuningDeletePresetBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？'**
  String tuningDeletePresetBody(String name);

  /// No description provided for @tuningDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get tuningDelete;

  /// No description provided for @tuningDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'删除失败：{error}'**
  String tuningDeleteFailed(String error);

  /// No description provided for @commonOk.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get commonOk;

  /// No description provided for @commonRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get commonRemove;

  /// No description provided for @commonDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get commonEdit;

  /// No description provided for @lossy.
  ///
  /// In zh, this message translates to:
  /// **'有损'**
  String get lossy;

  /// No description provided for @myMusic.
  ///
  /// In zh, this message translates to:
  /// **'我的音乐'**
  String get myMusic;

  /// No description provided for @favorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorites;

  /// No description provided for @noFavorites.
  ///
  /// In zh, this message translates to:
  /// **'暂无收藏'**
  String get noFavorites;

  /// No description provided for @noPlayHistory.
  ///
  /// In zh, this message translates to:
  /// **'暂无播放历史'**
  String get noPlayHistory;

  /// No description provided for @noPlaylistsHint.
  ///
  /// In zh, this message translates to:
  /// **'还没有歌单，点击右上角新建'**
  String get noPlaylistsHint;

  /// No description provided for @deletePlaylist.
  ///
  /// In zh, this message translates to:
  /// **'删除歌单'**
  String get deletePlaylist;

  /// No description provided for @deletePlaylistBody.
  ///
  /// In zh, this message translates to:
  /// **'确定删除「{name}」？'**
  String deletePlaylistBody(String name);

  /// No description provided for @playAll.
  ///
  /// In zh, this message translates to:
  /// **'播放全部'**
  String get playAll;

  /// No description provided for @addSongs.
  ///
  /// In zh, this message translates to:
  /// **'加入歌曲'**
  String get addSongs;

  /// No description provided for @noPlaylistSongs.
  ///
  /// In zh, this message translates to:
  /// **'这个歌单还没有歌曲'**
  String get noPlaylistSongs;

  /// No description provided for @noPlaylistSongsHint.
  ///
  /// In zh, this message translates to:
  /// **'点右上角 + 号，从收藏或最近播放里挑几首'**
  String get noPlaylistSongsHint;

  /// No description provided for @noSongsToAdd.
  ///
  /// In zh, this message translates to:
  /// **'暂无可添加的歌曲（先收藏或播放歌曲）'**
  String get noSongsToAdd;

  /// No description provided for @scanPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'扫描与维护'**
  String get scanPageTitle;

  /// No description provided for @scanStatusHeader.
  ///
  /// In zh, this message translates to:
  /// **'扫描状态'**
  String get scanStatusHeader;

  /// No description provided for @scanLibrary.
  ///
  /// In zh, this message translates to:
  /// **'曲库扫描'**
  String get scanLibrary;

  /// No description provided for @scanProgressLabel.
  ///
  /// In zh, this message translates to:
  /// **'扫描进度'**
  String get scanProgressLabel;

  /// No description provided for @scanLastDone.
  ///
  /// In zh, this message translates to:
  /// **'上次完成'**
  String get scanLastDone;

  /// No description provided for @scanLastStats.
  ///
  /// In zh, this message translates to:
  /// **'上次统计'**
  String get scanLastStats;

  /// No description provided for @scanFiles.
  ///
  /// In zh, this message translates to:
  /// **'扫描文件'**
  String get scanFiles;

  /// No description provided for @scanAddedUpdated.
  ///
  /// In zh, this message translates to:
  /// **'新增 / 更新'**
  String get scanAddedUpdated;

  /// No description provided for @scanRemoved.
  ///
  /// In zh, this message translates to:
  /// **'清理失效'**
  String get scanRemoved;

  /// No description provided for @scanSkipped.
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get scanSkipped;

  /// No description provided for @scanFailedCount.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get scanFailedCount;

  /// No description provided for @scanStart.
  ///
  /// In zh, this message translates to:
  /// **'开始扫描'**
  String get scanStart;

  /// No description provided for @scanFullRescan.
  ///
  /// In zh, this message translates to:
  /// **'全量重扫'**
  String get scanFullRescan;

  /// No description provided for @scanRootsHeader.
  ///
  /// In zh, this message translates to:
  /// **'扫描目录'**
  String get scanRootsHeader;

  /// No description provided for @scanRootsHint.
  ///
  /// In zh, this message translates to:
  /// **'只扫描这些根目录；移除目录仅停止扫描，已入库记录保留。'**
  String get scanRootsHint;

  /// No description provided for @scanNoRoots.
  ///
  /// In zh, this message translates to:
  /// **'暂无扫描目录'**
  String get scanNoRoots;

  /// No description provided for @scanRootEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用中'**
  String get scanRootEnabled;

  /// No description provided for @scanRootDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get scanRootDisabled;

  /// No description provided for @scanAddDir.
  ///
  /// In zh, this message translates to:
  /// **'添加目录'**
  String get scanAddDir;

  /// No description provided for @scanAddRootTitle.
  ///
  /// In zh, this message translates to:
  /// **'添加扫描目录'**
  String get scanAddRootTitle;

  /// No description provided for @scanRootPath.
  ///
  /// In zh, this message translates to:
  /// **'目录路径'**
  String get scanRootPath;

  /// No description provided for @scanRemoveRootTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除扫描目录'**
  String get scanRemoveRootTitle;

  /// No description provided for @scanRemoveRootBody.
  ///
  /// In zh, this message translates to:
  /// **'确定移除「{path}」？\n仅停止扫描该目录，已入库记录保留。'**
  String scanRemoveRootBody(String path);

  /// No description provided for @scanStatusLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'状态加载失败：{error}'**
  String scanStatusLoadFailed(String error);

  /// No description provided for @scanRunning.
  ///
  /// In zh, this message translates to:
  /// **'进行中 {progress}%'**
  String scanRunning(int progress);

  /// No description provided for @scanStartedFull.
  ///
  /// In zh, this message translates to:
  /// **'已开始全量重扫'**
  String get scanStartedFull;

  /// No description provided for @scanStartedIncremental.
  ///
  /// In zh, this message translates to:
  /// **'已开始增量扫描'**
  String get scanStartedIncremental;

  /// No description provided for @scanTriggerFailed.
  ///
  /// In zh, this message translates to:
  /// **'触发失败：{error}'**
  String scanTriggerFailed(String error);

  /// No description provided for @scanRootAdded.
  ///
  /// In zh, this message translates to:
  /// **'已添加目录'**
  String get scanRootAdded;

  /// No description provided for @scanRootAddFailed.
  ///
  /// In zh, this message translates to:
  /// **'添加失败：{error}'**
  String scanRootAddFailed(String error);

  /// No description provided for @scanRootRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除目录'**
  String get scanRootRemoved;

  /// No description provided for @scanRootRemoveFailed.
  ///
  /// In zh, this message translates to:
  /// **'移除失败：{error}'**
  String scanRootRemoveFailed(String error);

  /// No description provided for @devicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'输出设备'**
  String get devicesTitle;

  /// No description provided for @rescan.
  ///
  /// In zh, this message translates to:
  /// **'重新扫描'**
  String get rescan;

  /// No description provided for @availableDevices.
  ///
  /// In zh, this message translates to:
  /// **'可用设备'**
  String get availableDevices;

  /// No description provided for @deviceLocal.
  ///
  /// In zh, this message translates to:
  /// **'本机'**
  String get deviceLocal;

  /// No description provided for @clientAudioOut.
  ///
  /// In zh, this message translates to:
  /// **'音频输出'**
  String get clientAudioOut;

  /// No description provided for @scanFailed.
  ///
  /// In zh, this message translates to:
  /// **'扫描失败：{error}'**
  String scanFailed(String error);

  /// No description provided for @noDlnaRenderers.
  ///
  /// In zh, this message translates to:
  /// **'未发现 DLNA 渲染器'**
  String get noDlnaRenderers;

  /// No description provided for @outputParams.
  ///
  /// In zh, this message translates to:
  /// **'输出参数'**
  String get outputParams;

  /// No description provided for @deviceLabel.
  ///
  /// In zh, this message translates to:
  /// **'设备'**
  String get deviceLabel;

  /// No description provided for @sampleRatePolicy.
  ///
  /// In zh, this message translates to:
  /// **'采样率策略'**
  String get sampleRatePolicy;

  /// No description provided for @followSource.
  ///
  /// In zh, this message translates to:
  /// **'跟随源'**
  String get followSource;

  /// No description provided for @dsdPassThrough.
  ///
  /// In zh, this message translates to:
  /// **'DSD 原样送接收端'**
  String get dsdPassThrough;

  /// No description provided for @dsdExtractPoint.
  ///
  /// In zh, this message translates to:
  /// **'DSD 抽取落点'**
  String get dsdExtractPoint;

  /// No description provided for @eqFade.
  ///
  /// In zh, this message translates to:
  /// **'EQ / 淡入淡出'**
  String get eqFade;

  /// No description provided for @bypass.
  ///
  /// In zh, this message translates to:
  /// **'旁路'**
  String get bypass;

  /// No description provided for @nowPlayingLabel.
  ///
  /// In zh, this message translates to:
  /// **'正在播放：{song}'**
  String nowPlayingLabel(String song);

  /// No description provided for @selectSongFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择一首歌曲'**
  String get selectSongFirst;

  /// No description provided for @castSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已投屏到 {name}'**
  String castSuccess(String name);

  /// No description provided for @castFailed.
  ///
  /// In zh, this message translates to:
  /// **'投屏失败：{error}'**
  String castFailed(String error);

  /// No description provided for @backToLocal.
  ///
  /// In zh, this message translates to:
  /// **'已切回本机播放'**
  String get backToLocal;

  /// No description provided for @loginSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'飞牛 NAS 私有化 HIFI 流媒体'**
  String get loginSubtitle;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @restoreDefault.
  ///
  /// In zh, this message translates to:
  /// **'恢复默认地址'**
  String get restoreDefault;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get password;

  /// No description provided for @login.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get login;

  /// No description provided for @serverUrlEmpty.
  ///
  /// In zh, this message translates to:
  /// **'地址不能为空'**
  String get serverUrlEmpty;

  /// No description provided for @serverUrlScheme.
  ///
  /// In zh, this message translates to:
  /// **'地址必须以 http:// 或 https:// 开头'**
  String get serverUrlScheme;

  /// No description provided for @serverUrlHost.
  ///
  /// In zh, this message translates to:
  /// **'地址缺少主机名或 IP'**
  String get serverUrlHost;

  /// No description provided for @serverInvalid.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址有误：{error}'**
  String serverInvalid(String error);

  /// No description provided for @loginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败：{error}'**
  String loginFailed(String error);

  /// No description provided for @qualityTierTitle.
  ///
  /// In zh, this message translates to:
  /// **'音质档位'**
  String get qualityTierTitle;

  /// No description provided for @qualityLossless.
  ///
  /// In zh, this message translates to:
  /// **'无损 · 跟随源'**
  String get qualityLossless;

  /// No description provided for @qualityCd.
  ///
  /// In zh, this message translates to:
  /// **'无损 · 16 bit'**
  String get qualityCd;

  /// No description provided for @qualityHd.
  ///
  /// In zh, this message translates to:
  /// **'无损 · 24 bit'**
  String get qualityHd;

  /// No description provided for @playNext.
  ///
  /// In zh, this message translates to:
  /// **'下一首播放'**
  String get playNext;

  /// No description provided for @addedToPlayNext.
  ///
  /// In zh, this message translates to:
  /// **'已加入下一首播放'**
  String get addedToPlayNext;

  /// No description provided for @addToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'添加到歌单'**
  String get addToPlaylist;

  /// No description provided for @unfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get unfavorite;

  /// No description provided for @favorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get favorite;

  /// No description provided for @opFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String opFailed(String error);

  /// No description provided for @scrapeMetadata.
  ///
  /// In zh, this message translates to:
  /// **'联网刮削元数据'**
  String get scrapeMetadata;

  /// No description provided for @scrapeDone.
  ///
  /// In zh, this message translates to:
  /// **'刮削完成：歌词 {lyrics} 封面 {cover}'**
  String scrapeDone(String lyrics, String cover);

  /// No description provided for @noOnlineMatch.
  ///
  /// In zh, this message translates to:
  /// **'未找到在线匹配结果'**
  String get noOnlineMatch;

  /// No description provided for @scrapeFailed.
  ///
  /// In zh, this message translates to:
  /// **'刮削失败：{error}'**
  String scrapeFailed(String error);

  /// No description provided for @addedToPlaylist.
  ///
  /// In zh, this message translates to:
  /// **'已加入歌单'**
  String get addedToPlaylist;

  /// No description provided for @addToPlaylistFailed.
  ///
  /// In zh, this message translates to:
  /// **'加入失败：{error}'**
  String addToPlaylistFailed(String error);

  /// No description provided for @chooseDevice.
  ///
  /// In zh, this message translates to:
  /// **'选择播放设备'**
  String get chooseDevice;

  /// No description provided for @localPlayback.
  ///
  /// In zh, this message translates to:
  /// **'本机播放'**
  String get localPlayback;

  /// No description provided for @dlnaRenderer.
  ///
  /// In zh, this message translates to:
  /// **'DLNA 渲染器'**
  String get dlnaRenderer;

  /// No description provided for @castedTo.
  ///
  /// In zh, this message translates to:
  /// **'已投屏：{name}'**
  String castedTo(String name);

  /// No description provided for @signalPathTitle.
  ///
  /// In zh, this message translates to:
  /// **'信号路径'**
  String get signalPathTitle;

  /// No description provided for @notPlaying.
  ///
  /// In zh, this message translates to:
  /// **'未在播放'**
  String get notPlaying;

  /// No description provided for @rgNotEnabled.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get rgNotEnabled;

  /// No description provided for @rgMissingTag.
  ///
  /// In zh, this message translates to:
  /// **'该文件缺少标签，未调整'**
  String get rgMissingTag;

  /// No description provided for @rgLinearGain.
  ///
  /// In zh, this message translates to:
  /// **'线性增益 {gain}x'**
  String rgLinearGain(String gain);

  /// No description provided for @rgPeakCap.
  ///
  /// In zh, this message translates to:
  /// **'峰值封顶防削波'**
  String get rgPeakCap;

  /// No description provided for @dlnaPush.
  ///
  /// In zh, this message translates to:
  /// **'DLNA 推送'**
  String get dlnaPush;

  /// No description provided for @rendererFallback.
  ///
  /// In zh, this message translates to:
  /// **'渲染器'**
  String get rendererFallback;

  /// No description provided for @flacFollowSource.
  ///
  /// In zh, this message translates to:
  /// **'FLAC 跟随源'**
  String get flacFollowSource;

  /// No description provided for @httpStream.
  ///
  /// In zh, this message translates to:
  /// **'HTTP 音频流（服务端处理）'**
  String get httpStream;

  /// No description provided for @outParams.
  ///
  /// In zh, this message translates to:
  /// **'{label} · 48kHz'**
  String outParams(String label);

  /// No description provided for @httpDirect.
  ///
  /// In zh, this message translates to:
  /// **'HTTP 直出（原始文件）'**
  String get httpDirect;

  /// No description provided for @httpDirectSub.
  ///
  /// In zh, this message translates to:
  /// **'Range 字节流 · 服务端不处理'**
  String get httpDirectSub;

  /// No description provided for @sourceFile.
  ///
  /// In zh, this message translates to:
  /// **'源文件'**
  String get sourceFile;

  /// No description provided for @decodeToPcm.
  ///
  /// In zh, this message translates to:
  /// **'解码 {codec} → PCM'**
  String decodeToPcm(String codec);

  /// No description provided for @symphoniaDecode.
  ///
  /// In zh, this message translates to:
  /// **'symphonia 解码'**
  String get symphoniaDecode;

  /// No description provided for @resampleMix.
  ///
  /// In zh, this message translates to:
  /// **'重采样 / 混音'**
  String get resampleMix;

  /// No description provided for @resampleTarget.
  ///
  /// In zh, this message translates to:
  /// **'48kHz · 立体声'**
  String get resampleTarget;

  /// No description provided for @resamplePassthrough.
  ///
  /// In zh, this message translates to:
  /// **'直通，保持原始格式'**
  String get resamplePassthrough;

  /// No description provided for @presetWithName.
  ///
  /// In zh, this message translates to:
  /// **'音效预设 · {name}'**
  String presetWithName(String name);

  /// No description provided for @camillaDsp.
  ///
  /// In zh, this message translates to:
  /// **'camilladsp DSP'**
  String get camillaDsp;

  /// No description provided for @presetIdle.
  ///
  /// In zh, this message translates to:
  /// **'未启用 · 原声直通'**
  String get presetIdle;

  /// No description provided for @volumeMuted.
  ///
  /// In zh, this message translates to:
  /// **'音量 · 已静音'**
  String get volumeMuted;

  /// No description provided for @volumePercent.
  ///
  /// In zh, this message translates to:
  /// **'音量 {percent}%'**
  String volumePercent(int percent);

  /// No description provided for @clientVolume.
  ///
  /// In zh, this message translates to:
  /// **'本地音量'**
  String get clientVolume;

  /// No description provided for @dlnaRendererOutput.
  ///
  /// In zh, this message translates to:
  /// **'DLNA 渲染器'**
  String get dlnaRendererOutput;

  /// No description provided for @lyricsLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'歌词加载失败'**
  String get lyricsLoadFailed;

  /// No description provided for @noLyrics.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词'**
  String get noLyrics;

  /// No description provided for @noLyricsHint.
  ///
  /// In zh, this message translates to:
  /// **'可在 Web 端编辑或上传 LRC 文件'**
  String get noLyricsHint;

  /// No description provided for @levelMeter.
  ///
  /// In zh, this message translates to:
  /// **'电平'**
  String get levelMeter;

  /// No description provided for @relatedTitle.
  ///
  /// In zh, this message translates to:
  /// **'相关'**
  String get relatedTitle;

  /// No description provided for @relatedArtists.
  ///
  /// In zh, this message translates to:
  /// **'相关艺人'**
  String get relatedArtists;

  /// No description provided for @noSameArtist.
  ///
  /// In zh, this message translates to:
  /// **'曲库里暂无同艺人作品'**
  String get noSameArtist;

  /// No description provided for @relatedAlbums.
  ///
  /// In zh, this message translates to:
  /// **'相关专辑'**
  String get relatedAlbums;

  /// No description provided for @noSameAlbum.
  ///
  /// In zh, this message translates to:
  /// **'曲库里暂无同专辑作品'**
  String get noSameAlbum;

  /// No description provided for @youMayLike.
  ///
  /// In zh, this message translates to:
  /// **'你可能也喜欢'**
  String get youMayLike;

  /// No description provided for @noRecommendations.
  ///
  /// In zh, this message translates to:
  /// **'暂无推荐'**
  String get noRecommendations;

  /// No description provided for @lyrics.
  ///
  /// In zh, this message translates to:
  /// **'歌词'**
  String get lyrics;

  /// No description provided for @lyricsWithTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌词 · {title}'**
  String lyricsWithTitle(String title);

  /// No description provided for @uploadLrc.
  ///
  /// In zh, this message translates to:
  /// **'上传 LRC'**
  String get uploadLrc;

  /// No description provided for @lyricsSaved.
  ///
  /// In zh, this message translates to:
  /// **'歌词已保存（来源：手动编辑）'**
  String get lyricsSaved;

  /// No description provided for @uploadSuccess.
  ///
  /// In zh, this message translates to:
  /// **'上传成功：{name}'**
  String uploadSuccess(String name);

  /// No description provided for @uploadFailed.
  ///
  /// In zh, this message translates to:
  /// **'上传失败：{error}'**
  String uploadFailed(String error);

  /// No description provided for @lyricsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌词，可点击「编辑」或「上传 LRC」'**
  String get lyricsEmptyHint;

  /// No description provided for @lyricsPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'[00:00.00]第一行歌词\n[00:03.00]第二行歌词'**
  String get lyricsPlaceholder;

  /// No description provided for @lyricSourceUser.
  ///
  /// In zh, this message translates to:
  /// **'手动编辑'**
  String get lyricSourceUser;

  /// No description provided for @lyricSourceEmbedded.
  ///
  /// In zh, this message translates to:
  /// **'音频内嵌'**
  String get lyricSourceEmbedded;

  /// No description provided for @lyricSourceFile.
  ///
  /// In zh, this message translates to:
  /// **'LRC 文件'**
  String get lyricSourceFile;

  /// No description provided for @lyricSourceNetwork.
  ///
  /// In zh, this message translates to:
  /// **'网络刮削'**
  String get lyricSourceNetwork;

  /// No description provided for @lyricSourceNone.
  ///
  /// In zh, this message translates to:
  /// **'无歌词'**
  String get lyricSourceNone;

  /// No description provided for @rgAnalyzeDone.
  ///
  /// In zh, this message translates to:
  /// **'分析完成：实测 {measured} · 跳过 {skipped} · 失败 {failed}'**
  String rgAnalyzeDone(int measured, int skipped, int failed);

  /// No description provided for @rgAnalyzeFailed.
  ///
  /// In zh, this message translates to:
  /// **'分析失败：{error}'**
  String rgAnalyzeFailed(String error);

  /// No description provided for @rgMeasureHeader.
  ///
  /// In zh, this message translates to:
  /// **'实测口径'**
  String get rgMeasureHeader;

  /// No description provided for @rgKWeighting.
  ///
  /// In zh, this message translates to:
  /// **'K 计权 + 400ms / 100ms 分块 + 双重门限'**
  String get rgKWeighting;

  /// No description provided for @rgTruePeak.
  ///
  /// In zh, this message translates to:
  /// **'真峰值（附录 2）参与防削波'**
  String get rgTruePeak;

  /// No description provided for @rgImplemented.
  ///
  /// In zh, this message translates to:
  /// **'已实现'**
  String get rgImplemented;

  /// No description provided for @rgByChannelLayout.
  ///
  /// In zh, this message translates to:
  /// **'按源声道布局测量'**
  String get rgByChannelLayout;

  /// No description provided for @rgCorrect.
  ///
  /// In zh, this message translates to:
  /// **'正确'**
  String get rgCorrect;

  /// No description provided for @rgAlbumGainWeighted.
  ///
  /// In zh, this message translates to:
  /// **'专辑增益按时长加权能量合成'**
  String get rgAlbumGainWeighted;

  /// No description provided for @rgAnalyzeMissing.
  ///
  /// In zh, this message translates to:
  /// **'分析缺失曲目'**
  String get rgAnalyzeMissing;

  /// No description provided for @rgReanalyzeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部重新分析'**
  String get rgReanalyzeAll;

  /// No description provided for @rgStatusLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'状态加载失败：{error}'**
  String rgStatusLoadFailed(String error);

  /// No description provided for @rgRefLevel.
  ///
  /// In zh, this message translates to:
  /// **'参考电平 LUFS'**
  String get rgRefLevel;

  /// No description provided for @rgAnalyzedCount.
  ///
  /// In zh, this message translates to:
  /// **'首已实测'**
  String get rgAnalyzedCount;

  /// No description provided for @rgPendingCount.
  ///
  /// In zh, this message translates to:
  /// **'首待分析'**
  String get rgPendingCount;

  /// No description provided for @rgTaggedCount.
  ///
  /// In zh, this message translates to:
  /// **'标签曲目'**
  String get rgTaggedCount;

  /// No description provided for @libTabSongs.
  ///
  /// In zh, this message translates to:
  /// **'歌曲'**
  String get libTabSongs;

  /// No description provided for @libTabAlbums.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get libTabAlbums;

  /// No description provided for @libTabArtists.
  ///
  /// In zh, this message translates to:
  /// **'歌手'**
  String get libTabArtists;

  /// No description provided for @libTabGenres.
  ///
  /// In zh, this message translates to:
  /// **'风格'**
  String get libTabGenres;

  /// No description provided for @albumsTitle.
  ///
  /// In zh, this message translates to:
  /// **'专辑'**
  String get albumsTitle;

  /// No description provided for @artistsTitle.
  ///
  /// In zh, this message translates to:
  /// **'歌手'**
  String get artistsTitle;

  /// No description provided for @genresTitle.
  ///
  /// In zh, this message translates to:
  /// **'风格'**
  String get genresTitle;

  /// No description provided for @noAlbums.
  ///
  /// In zh, this message translates to:
  /// **'暂无专辑'**
  String get noAlbums;

  /// No description provided for @noArtists.
  ///
  /// In zh, this message translates to:
  /// **'暂无歌手'**
  String get noArtists;

  /// No description provided for @noGenres.
  ///
  /// In zh, this message translates to:
  /// **'暂无风格'**
  String get noGenres;

  /// No description provided for @unknownArtist.
  ///
  /// In zh, this message translates to:
  /// **'未知艺术家'**
  String get unknownArtist;

  /// No description provided for @unknownYear.
  ///
  /// In zh, this message translates to:
  /// **'未知年份'**
  String get unknownYear;

  /// No description provided for @unknownGenre.
  ///
  /// In zh, this message translates to:
  /// **'未知风格'**
  String get unknownGenre;

  /// No description provided for @followArtist.
  ///
  /// In zh, this message translates to:
  /// **'关注'**
  String get followArtist;

  /// No description provided for @followingArtist.
  ///
  /// In zh, this message translates to:
  /// **'已关注'**
  String get followingArtist;

  /// No description provided for @followFailed.
  ///
  /// In zh, this message translates to:
  /// **'操作失败：{error}'**
  String followFailed(String error);

  /// No description provided for @itemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String itemCount(int count);

  /// No description provided for @albumCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张专辑'**
  String albumCount(int count);

  /// No description provided for @followedArtists.
  ///
  /// In zh, this message translates to:
  /// **'关注歌手'**
  String get followedArtists;

  /// No description provided for @dailyRecommendations.
  ///
  /// In zh, this message translates to:
  /// **'每日推荐'**
  String get dailyRecommendations;

  /// No description provided for @refreshRecommendations.
  ///
  /// In zh, this message translates to:
  /// **'换一批'**
  String get refreshRecommendations;

  /// No description provided for @recommendationEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无推荐，先去收藏或播放一些歌曲'**
  String get recommendationEmpty;

  /// No description provided for @roamTitle.
  ///
  /// In zh, this message translates to:
  /// **'漫游'**
  String get roamTitle;

  /// No description provided for @roamSimilar.
  ///
  /// In zh, this message translates to:
  /// **'相似漫游'**
  String get roamSimilar;

  /// No description provided for @roamTaste.
  ///
  /// In zh, this message translates to:
  /// **'口味漫游'**
  String get roamTaste;

  /// No description provided for @roamRandom.
  ///
  /// In zh, this message translates to:
  /// **'随机漫游'**
  String get roamRandom;

  /// No description provided for @roamStop.
  ///
  /// In zh, this message translates to:
  /// **'结束漫游'**
  String get roamStop;

  /// No description provided for @roamHint.
  ///
  /// In zh, this message translates to:
  /// **'按相似、口味或随机持续播放，播到队尾自动续接'**
  String get roamHint;

  /// No description provided for @setPlaylistCover.
  ///
  /// In zh, this message translates to:
  /// **'设为封面'**
  String get setPlaylistCover;

  /// No description provided for @moveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get moveDown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

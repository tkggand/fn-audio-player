// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FN Audio';

  @override
  String get tabHome => 'Home';

  @override
  String get tabClips => 'Clips';

  @override
  String get tabLibrary => 'Library';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Off';

  @override
  String get commonRetry => 'Retry';

  @override
  String get meTitle => 'Me';

  @override
  String get meGuest => 'Not signed in';

  @override
  String get meAccountAdmin => 'Administrator';

  @override
  String get meAccountLocal => 'Local library';

  @override
  String get groupAudio => 'Audio';

  @override
  String get groupPlaybackLibrary => 'Playback & Library';

  @override
  String get groupSystem => 'System';

  @override
  String get groupPlayback => 'Playback';

  @override
  String get meEqEffects => 'Equalizer & Effects';

  @override
  String get meEqDefault => 'Flat';

  @override
  String get meEqEnabled => 'Enabled';

  @override
  String get meQualityTier => 'Quality';

  @override
  String get rgModeTitle => 'ReplayGain Mode';

  @override
  String get rgOff => 'Off';

  @override
  String get rgTrack => 'Per track';

  @override
  String get rgAlbum => 'Per album';

  @override
  String get meFade => 'Fade';

  @override
  String fadeSeconds(String seconds) {
    return '${seconds}s';
  }

  @override
  String get meDevice => 'Output Device';

  @override
  String get meDeviceLocal => 'This device';

  @override
  String get meSignalPath => 'Signal Path';

  @override
  String get meScanLibrary => 'Scan Library';

  @override
  String get scanLoading => 'Loading…';

  @override
  String scanProgress(int percent) {
    return 'Scanning $percent%';
  }

  @override
  String get scanIdle => 'Idle';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get logout => 'Sign Out';

  @override
  String get logoutConfirmTitle => 'Sign Out';

  @override
  String get logoutConfirmBody => 'Sign out of this account?';

  @override
  String get logoutAction => 'Sign Out';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingSoftMute => 'Soft mute on pause';

  @override
  String get settingAutoPlayNext => 'Autoplay next';

  @override
  String get settingSyncEnabled => 'Sync playback across devices';

  @override
  String get settingBackendUrl => 'Server Address';

  @override
  String get settingDspJobs => 'Transcode Jobs';

  @override
  String get serverAddressTitle => 'Server Address';

  @override
  String get serverAddressHint =>
      'You must sign in again after changing the server.';

  @override
  String get serverSaveAndRelogin => 'Save & Sign In';

  @override
  String get language => 'Language';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageSystem => 'System';

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get playerNoSong => 'No song selected';

  @override
  String playbackFailed(String error) {
    return 'Playback failed: $error';
  }

  @override
  String playerOpFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String castingTo(String name) {
    return 'Casting to $name';
  }

  @override
  String get playerFx => 'Audio Effects';

  @override
  String get playerEqReplayGain => 'EQ preset · ReplayGain';

  @override
  String get playerPassthrough => 'Direct passthrough';

  @override
  String get more => 'More';

  @override
  String moreQueueSummary(int count, String artist) {
    return '$count queued · $artist';
  }

  @override
  String get moreUpNext => 'Up Next';

  @override
  String get moreQueue => 'Queue';

  @override
  String get moreLyrics => 'Lyrics';

  @override
  String get moreLyricsSub => 'Line synced';

  @override
  String get moreRelated => 'Related';

  @override
  String get moreRelatedSub => 'Artist · Album';

  @override
  String get moreSignalPath => 'Signal Path';

  @override
  String get moreSignalPathSub => 'Full processing chain';

  @override
  String get moreDevice => 'Output Device';

  @override
  String get moreDeviceSub => 'This device / DLNA';

  @override
  String get loadFailed => 'Failed to load';

  @override
  String get loadFailedTip =>
      'Check your network or backend service, then try again';

  @override
  String loadFailedWith(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get noHistory => 'No play history yet';

  @override
  String get homeTitle => 'Home';

  @override
  String get recentPlayed => 'Recently Played';

  @override
  String get continueListening => 'Continue Listening';

  @override
  String get clipsTitle => 'Clips';

  @override
  String get clipsEmpty => 'No clips yet';

  @override
  String get clipsUnavailable =>
      'The server does not expose a video clips API yet. Live, cover and favorite clips will appear here once it is available.';

  @override
  String get filterAll => 'All';

  @override
  String get filterLive => 'Live';

  @override
  String get filterCover => 'Covers';

  @override
  String get filterFavorites => 'Favorites';

  @override
  String get filterRecent => 'Recent';

  @override
  String get filterLossy => 'Lossy';

  @override
  String get libraryTitle => 'Library';

  @override
  String get playlistsTitle => 'Playlists';

  @override
  String get allSongs => 'All Songs';

  @override
  String songCount(int count) {
    return '$count songs';
  }

  @override
  String get noPlaylists => 'No playlists yet. Tap + to create one.';

  @override
  String get playlistsLoadFailed => 'Failed to load playlists';

  @override
  String get noMatchedSongs => 'No matching songs';

  @override
  String get noMatchedAlbums => 'No matching albums';

  @override
  String get noMatchedArtists => 'No matching artists';

  @override
  String get noMatchedPlaylists => 'No matching playlists';

  @override
  String get newPlaylist => 'New Playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get create => 'Create';

  @override
  String createFailed(String error) {
    return 'Create failed: $error';
  }

  @override
  String playlistSongCount(int count) {
    return 'Playlist · $count songs';
  }

  @override
  String artistSongCount(String artist, int count) {
    return '$artist · $count songs';
  }

  @override
  String get queueEmpty => 'Queue is empty';

  @override
  String get searchSongs => 'Songs';

  @override
  String get searchAlbums => 'Albums';

  @override
  String get searchArtists => 'Artists';

  @override
  String get searchPlaylists => 'Playlists';

  @override
  String get searchHint => 'Songs, albums, artists';

  @override
  String get searchStart => 'Type a keyword to search';

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String get historyTitle => 'History';

  @override
  String get tuningTitle => 'Tuning';

  @override
  String get tuningEqualizer => 'Equalizer';

  @override
  String tuningToggleFailed(String error) {
    return 'Failed to toggle: $error';
  }

  @override
  String get tuningEqCleared => 'Equalizer cleared';

  @override
  String tuningEqClearFailed(String error) {
    return 'Failed to clear: $error';
  }

  @override
  String tuningApplyFailed(String error) {
    return 'Failed to apply: $error';
  }

  @override
  String get tuningPeqApplied => 'PEQ applied';

  @override
  String get tuningClear => 'Clear';

  @override
  String get tuningFadeIn => 'Fade in';

  @override
  String get tuningFadeOut => 'Fade out';

  @override
  String get tuningFadesSaved => 'Fade settings saved';

  @override
  String tuningBandCount(int count) {
    return '$count bands';
  }

  @override
  String get tuningPresetLabel => 'Preset';

  @override
  String get tuningPresets => 'Sound Presets';

  @override
  String get tuningPresetNone => 'Original (no effects)';

  @override
  String get tuningPresetSystem => 'System';

  @override
  String get tuningAddBand => 'Add Band';

  @override
  String get tuningApply => 'Apply';

  @override
  String get tuningBandType => 'Band type';

  @override
  String get tuningAutoeqHint =>
      'Paste AutoEq parameter text, e.g.:\nPreamp: -6.2 dB\nFilter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70';

  @override
  String get tuningAutoeqPaste => 'Paste AutoEq parameter text first';

  @override
  String get tuningImportApply => 'Import & Apply';

  @override
  String tuningImportOk(int count) {
    return 'Imported $count bands';
  }

  @override
  String tuningImportOkWithHeadroom(int count, String headroom) {
    return 'Imported $count bands, ${headroom}dB headroom reserved';
  }

  @override
  String get tuningImportNotOk => 'Import unsuccessful';

  @override
  String tuningImportError(String error) {
    return 'Import failed: $error';
  }

  @override
  String get tuningDeletePresetTitle => 'Delete Preset';

  @override
  String tuningDeletePresetBody(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get tuningDelete => 'Delete';

  @override
  String tuningDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get commonOk => 'OK';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get lossy => 'Lossy';

  @override
  String get myMusic => 'My Music';

  @override
  String get favorites => 'Favorites';

  @override
  String get noFavorites => 'No favorites yet';

  @override
  String get noPlayHistory => 'No play history yet';

  @override
  String get noPlaylistsHint =>
      'No playlists yet. Tap + at the top right to create one';

  @override
  String get deletePlaylist => 'Delete Playlist';

  @override
  String deletePlaylistBody(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get playAll => 'Play All';

  @override
  String get addSongs => 'Add Songs';

  @override
  String get noPlaylistSongs => 'This playlist is empty';

  @override
  String get noPlaylistSongsHint =>
      'Tap + to pick songs from favorites or recent plays';

  @override
  String get noSongsToAdd => 'No songs to add (favorite or play some first)';

  @override
  String get scanPageTitle => 'Scan & Maintenance';

  @override
  String get scanStatusHeader => 'Scan Status';

  @override
  String get scanLibrary => 'Library Scan';

  @override
  String get scanProgressLabel => 'Scan Progress';

  @override
  String get scanLastDone => 'Last Finished';

  @override
  String get scanLastStats => 'Last Run';

  @override
  String get scanFiles => 'Files Scanned';

  @override
  String get scanAddedUpdated => 'Added / Updated';

  @override
  String get scanRemoved => 'Removed';

  @override
  String get scanSkipped => 'Skipped';

  @override
  String get scanFailedCount => 'Failed';

  @override
  String get scanStart => 'Start Scan';

  @override
  String get scanFullRescan => 'Full Rescan';

  @override
  String get scanRootsHeader => 'Scan Folders';

  @override
  String get scanRootsHint =>
      'Only these root folders are scanned. Removing a folder stops scanning it but keeps indexed records.';

  @override
  String get scanNoRoots => 'No scan folders';

  @override
  String get scanRootEnabled => 'Enabled';

  @override
  String get scanRootDisabled => 'Disabled';

  @override
  String get scanAddDir => 'Add Folder';

  @override
  String get scanAddRootTitle => 'Add Scan Folder';

  @override
  String get scanRootPath => 'Folder path';

  @override
  String get scanRemoveRootTitle => 'Remove Scan Folder';

  @override
  String scanRemoveRootBody(String path) {
    return 'Remove \"$path\"?\nScanning stops for this folder; indexed records are kept.';
  }

  @override
  String scanStatusLoadFailed(String error) {
    return 'Failed to load status: $error';
  }

  @override
  String scanRunning(int progress) {
    return 'Running $progress%';
  }

  @override
  String get scanStartedFull => 'Full rescan started';

  @override
  String get scanStartedIncremental => 'Incremental scan started';

  @override
  String scanTriggerFailed(String error) {
    return 'Failed to trigger: $error';
  }

  @override
  String get scanRootAdded => 'Folder added';

  @override
  String scanRootAddFailed(String error) {
    return 'Failed to add: $error';
  }

  @override
  String get scanRootRemoved => 'Folder removed';

  @override
  String scanRootRemoveFailed(String error) {
    return 'Failed to remove: $error';
  }

  @override
  String get devicesTitle => 'Output Devices';

  @override
  String get rescan => 'Rescan';

  @override
  String get availableDevices => 'Available Devices';

  @override
  String get deviceLocal => 'This device';

  @override
  String get clientAudioOut => 'Client audio output';

  @override
  String scanFailed(String error) {
    return 'Scan failed: $error';
  }

  @override
  String get noDlnaRenderers => 'No DLNA renderers found';

  @override
  String get outputParams => 'Output Parameters';

  @override
  String get deviceLabel => 'Device';

  @override
  String get sampleRatePolicy => 'Sample rate policy';

  @override
  String get followSource => 'Follow source';

  @override
  String get dsdPassThrough => 'Pass DSD through to receiver';

  @override
  String get dsdExtractPoint => 'DSD extraction point';

  @override
  String get eqFade => 'EQ / Fade';

  @override
  String get bypass => 'Bypass';

  @override
  String nowPlayingLabel(String song) {
    return 'Now playing: $song';
  }

  @override
  String get selectSongFirst => 'Select a song first';

  @override
  String castSuccess(String name) {
    return 'Casting to $name';
  }

  @override
  String castFailed(String error) {
    return 'Cast failed: $error';
  }

  @override
  String get backToLocal => 'Switched back to local playback';

  @override
  String get loginSubtitle => 'Private HiFi streaming on FNOS NAS';

  @override
  String get serverAddress => 'Server address';

  @override
  String get restoreDefault => 'Restore default address';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get login => 'Sign In';

  @override
  String get serverUrlEmpty => 'Address cannot be empty';

  @override
  String get serverUrlScheme => 'Address must start with http:// or https://';

  @override
  String get serverUrlHost => 'Address is missing a host name or IP';

  @override
  String serverInvalid(String error) {
    return 'Invalid server address: $error';
  }

  @override
  String loginFailed(String error) {
    return 'Sign-in failed: $error';
  }

  @override
  String get qualityTierTitle => 'Quality Tier';

  @override
  String get qualityLossless => 'Lossless · Follow source';

  @override
  String get qualityCd => 'Lossless · 16 bit';

  @override
  String get qualityHd => 'Lossless · 24 bit';

  @override
  String get playNext => 'Play Next';

  @override
  String get addedToPlayNext => 'Added to play next';

  @override
  String get addToPlaylist => 'Add to Playlist';

  @override
  String get unfavorite => 'Remove Favorite';

  @override
  String get favorite => 'Favorite';

  @override
  String opFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get lyricsEdit => 'Lyrics View / Edit';

  @override
  String get scrapeMetadata => 'Scrape Online Metadata';

  @override
  String scrapeDone(String lyrics, String cover) {
    return 'Scrape done: lyrics $lyrics cover $cover';
  }

  @override
  String get noOnlineMatch => 'No online match found';

  @override
  String scrapeFailed(String error) {
    return 'Scrape failed: $error';
  }

  @override
  String get addedToPlaylist => 'Added to playlist';

  @override
  String addToPlaylistFailed(String error) {
    return 'Failed to add: $error';
  }

  @override
  String get chooseDevice => 'Choose Playback Device';

  @override
  String get localPlayback => 'This device';

  @override
  String get dlnaRenderer => 'DLNA renderer';

  @override
  String castedTo(String name) {
    return 'Casting: $name';
  }

  @override
  String get signalPathTitle => 'Signal Path';

  @override
  String get notPlaying => 'Nothing playing';

  @override
  String get rgNotEnabled => 'Not enabled';

  @override
  String get rgMissingTag => 'Missing tags for this file; no adjustment';

  @override
  String rgLinearGain(String gain) {
    return 'Linear gain ${gain}x';
  }

  @override
  String get rgPeakCap => 'Peak capped to prevent clipping';

  @override
  String get dlnaPush => 'DLNA Cast';

  @override
  String get rendererFallback => 'Renderer';

  @override
  String get flacFollowSource => 'FLAC follow source';

  @override
  String get httpStream => 'HTTP audio stream (server-side processing)';

  @override
  String outParams(String label) {
    return '$label · 48kHz stereo';
  }

  @override
  String get httpDirect => 'HTTP direct (original file)';

  @override
  String get httpDirectSub =>
      'Byte-stream Range seeking · no server processing';

  @override
  String get sourceFile => 'Source file';

  @override
  String decodeToPcm(String codec) {
    return 'Decode $codec → PCM';
  }

  @override
  String get symphoniaDecode => 'symphonia server-side decode';

  @override
  String get resampleMix => 'Resample / Mix';

  @override
  String resampleTarget(String source) {
    return '$source → 48kHz · stereo';
  }

  @override
  String get resamplePassthrough => 'Passthrough, keep original format';

  @override
  String presetWithName(String name) {
    return 'Preset · $name';
  }

  @override
  String get camillaDsp => 'camilladsp DSP chain';

  @override
  String get presetIdle => 'Disabled · original passthrough';

  @override
  String get volumeMuted => 'Volume · Muted';

  @override
  String volumePercent(int percent) {
    return 'Volume $percent%';
  }

  @override
  String get clientVolume => 'Client local volume';

  @override
  String get dlnaRendererOutput => 'DLNA renderer output';

  @override
  String get lyricsLoadFailed => 'Failed to load lyrics';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get noLyricsHint => 'Edit or upload an LRC file in the web app';

  @override
  String get levelMeter => 'Level';

  @override
  String get relatedTitle => 'Related';

  @override
  String get relatedArtists => 'Related Artists';

  @override
  String get noSameArtist => 'No other songs by this artist in the library';

  @override
  String get relatedAlbums => 'Related Albums';

  @override
  String get noSameAlbum => 'No other songs from this album in the library';

  @override
  String get youMayLike => 'You May Also Like';

  @override
  String get noRecommendations => 'No recommendations';

  @override
  String get lyrics => 'Lyrics';

  @override
  String lyricsWithTitle(String title) {
    return 'Lyrics · $title';
  }

  @override
  String get uploadLrc => 'Upload LRC';

  @override
  String get lyricsSaved => 'Lyrics saved (source: manual edit)';

  @override
  String uploadSuccess(String name) {
    return 'Uploaded: $name';
  }

  @override
  String uploadFailed(String error) {
    return 'Upload failed: $error';
  }

  @override
  String get lyricsEmptyHint => 'No lyrics yet. Tap Edit or Upload LRC';

  @override
  String get lyricsPlaceholder =>
      '[00:00.00]First lyric line\n[00:03.00]Second lyric line';

  @override
  String get lyricSourceUser => 'Manual edit';

  @override
  String get lyricSourceEmbedded => 'Embedded in audio';

  @override
  String get lyricSourceFile => 'LRC file';

  @override
  String get lyricSourceNetwork => 'Online scrape';

  @override
  String get lyricSourceNone => 'No lyrics';

  @override
  String rgAnalyzeDone(int measured, int skipped, int failed) {
    return 'Analysis done: measured $measured · skipped $skipped · failed $failed';
  }

  @override
  String rgAnalyzeFailed(String error) {
    return 'Analysis failed: $error';
  }

  @override
  String get rgMeasureHeader => 'Measurement Standard';

  @override
  String get rgKWeighting => 'K-weighting + 400ms / 100ms blocks + dual gating';

  @override
  String get rgTruePeak => 'True peak (Annex 2) prevents clipping';

  @override
  String get rgImplemented => 'Implemented';

  @override
  String get rgByChannelLayout => 'Measured by source channel layout';

  @override
  String get rgCorrect => 'Correct';

  @override
  String get rgAlbumGainWeighted => 'Album gain weighted by duration';

  @override
  String get rgAnalyzeMissing => 'Analyze Missing Tracks';

  @override
  String get rgReanalyzeAll => 'Re-analyze All';

  @override
  String rgStatusLoadFailed(String error) {
    return 'Failed to load status: $error';
  }

  @override
  String get rgRefLevel => 'Reference level LUFS';

  @override
  String get rgAnalyzedCount => 'analyzed';

  @override
  String get rgPendingCount => 'pending';

  @override
  String get rgTaggedCount => 'tagged';

  @override
  String get libTabSongs => 'Songs';

  @override
  String get libTabAlbums => 'Albums';

  @override
  String get libTabArtists => 'Artists';

  @override
  String get libTabGenres => 'Genres';

  @override
  String get albumsTitle => 'Albums';

  @override
  String get artistsTitle => 'Artists';

  @override
  String get genresTitle => 'Genres';

  @override
  String get noAlbums => 'No albums yet';

  @override
  String get noArtists => 'No artists yet';

  @override
  String get noGenres => 'No genres yet';

  @override
  String get unknownArtist => 'Unknown artist';

  @override
  String get unknownYear => 'Unknown year';

  @override
  String get unknownGenre => 'Unknown genre';

  @override
  String get followArtist => 'Follow';

  @override
  String get followingArtist => 'Following';

  @override
  String followFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String itemCount(int count) {
    return '$count items';
  }

  @override
  String albumCount(int count) {
    return '$count albums';
  }

  @override
  String get followedArtists => 'Followed Artists';

  @override
  String get dailyRecommendations => 'Daily Picks';

  @override
  String get refreshRecommendations => 'Refresh';

  @override
  String get recommendationEmpty =>
      'No picks yet. Favorite or play some songs first';

  @override
  String get roamTitle => 'Roam';

  @override
  String get roamSimilar => 'Similar';

  @override
  String get roamTaste => 'Taste';

  @override
  String get roamRandom => 'Random';

  @override
  String get roamStop => 'Stop Roam';

  @override
  String get roamHint =>
      'Keep playing similar, taste-based or random songs; the queue extends automatically';

  @override
  String get setPlaylistCover => 'Set as Cover';

  @override
  String get moveUp => 'Move Up';

  @override
  String get moveDown => 'Move Down';
}

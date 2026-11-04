import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../player_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 曲目菜单浮层（对应设计稿 15）：
/// 下一首播放 / 添加到歌单 / 收藏 / 歌词 / 联网刮削。
///
/// 后端暂无「删除曲库歌曲」「下载」「分享」接口，对应行不展示，避免假按钮。
Future<void> showTrackMenu(
  BuildContext context,
  Song song, {
  bool isFavorite = false,
  VoidCallback? onFavoriteChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: FnColors.barrier,
    builder: (sheetContext) => _TrackMenuSheet(
      song: song,
      isFavorite: isFavorite,
      onFavoriteChanged: onFavoriteChanged,
    ),
  );
}

class _TrackMenuSheet extends StatefulWidget {
  const _TrackMenuSheet({
    required this.song,
    required this.isFavorite,
    this.onFavoriteChanged,
  });

  final Song song;
  final bool isFavorite;
  final VoidCallback? onFavoriteChanged;

  @override
  State<_TrackMenuSheet> createState() => _TrackMenuSheetState();
}

class _TrackMenuSheetState extends State<_TrackMenuSheet> {
  late bool _fav = widget.isFavorite;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final song = widget.song;
    return Container(
      decoration: BoxDecoration(
        color: FnColors.raisedHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: FnColors.glassShadow,
            blurRadius: 40,
            offset: const Offset(0, -20),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const FnSheetHandle(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/player');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 14),
                      child: Row(
                        children: [
                          FnCover(songId: song.id, size: 52, radius: 6),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: FnColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${song.artist} · ${song.album}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: FnColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(CupertinoIcons.chevron_forward,
                              size: 18, color: FnColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                  _Option(
                    icon: CupertinoIcons.forward_end,
                    label: l.playNext,
                    onTap: () {
                      PlayerController.instance.playNext(song);
                      Navigator.pop(context);
                      _toast(l.addedToPlayNext);
                    },
                  ),
                  _Option(
                    icon: CupertinoIcons.plus,
                    label: l.addToPlaylist,
                    onTap: () async {
                      Navigator.pop(context);
                      await _addToPlaylist(song);
                    },
                  ),
                  _Option(
                    icon:
                        _fav ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    label: _fav ? l.unfavorite : l.favorite,
                    onTap: () async {
                      final nav = Navigator.of(context);
                      setState(() => _fav = !_fav);
                      try {
                        if (_fav) {
                          await ApiClient.instance.addFavorite(song.id);
                        } else {
                          await ApiClient.instance.removeFavorite(song.id);
                        }
                        widget.onFavoriteChanged?.call();
                        nav.pop();
                      } catch (e) {
                        if (mounted) {
                          setState(() => _fav = !_fav);
                          _toast(l.opFailed('$e'));
                        }
                      }
                    },
                  ),
                  if (ApiClient.instance.isAdmin)
                    _Option(
                      icon: CupertinoIcons.globe,
                      label: l.scrapeMetadata,
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          final r =
                              await ApiClient.instance.scrapeSong(song.id);
                          _toast(r.found
                              ? l.scrapeDone(r.gotLyrics ? '✓' : '—',
                                  r.gotCover ? '✓' : '—')
                              : l.noOnlineMatch);
                        } catch (e) {
                          _toast(l.scrapeFailed('$e'));
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addToPlaylist(Song song) async {
    final l = context.l10n;
    try {
      final lists = await ApiClient.instance.fetchPlaylists();
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        backgroundColor: FnColors.raisedHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(l.addToPlaylist,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
              GroupRow(
                leading: Icon(CupertinoIcons.add,
                    size: 20, color: FnColors.textPrimary),
                title: l.newPlaylist,
                onTap: () => Navigator.pop(c, -1),
              ),
              for (final p in lists) ...[
                const GroupDivider(indent: 52),
                GroupRow(
                  leading: Icon(CupertinoIcons.music_note_2,
                      size: 20, color: FnColors.textSecondary),
                  title: p.name,
                  subtitle: l.songCount(p.songCount),
                  onTap: () => Navigator.pop(c, p.id),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      if (picked == null) return;
      var playlistId = picked;
      if (picked == -1) {
        final name = await _promptText(l.newPlaylist, l.playlistName);
        if (name == null || name.isEmpty) return;
        final p = await ApiClient.instance.createPlaylist(name);
        playlistId = p.id;
      }
      await ApiClient.instance.addPlaylistTrack(playlistId, song.id);
      _toast(l.addedToPlaylist);
    } catch (e) {
      _toast(l.addToPlaylistFailed('$e'));
    }
  }

  Future<String?> _promptText(String title, String label) {
    final l = context.l10n;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(l.commonCancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(l.commonOk)),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: FnColors.divider),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Icon(icon, size: 19, color: FnColors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: FnColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

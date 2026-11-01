import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// 本地播放日志：后端 `/api/history` 只返回去重歌曲、不含时间戳，
/// 「我的 · 本周聆听」需要按天聚合，因此在客户端补一份轻量日志。
///
/// 只存 `[毫秒时间戳, 艺人, 歌曲 id]`，最多保留 2000 条；不参与任何同步。
class PlayLog {
  PlayLog._();
  static final PlayLog instance = PlayLog._();

  static const _key = 'fn_play_log_v2';
  static const _maxEntries = 2000;

  List<List<dynamic>>? _cache;

  Future<List<List<dynamic>>> _read() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _cache = [];
      return _cache!;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<List<dynamic>>();
      _cache = list;
    } catch (_) {
      _cache = [];
    }
    return _cache!;
  }

  Future<void> record(Song song) async {
    final log = await _read();
    log.add([DateTime.now().millisecondsSinceEpoch, song.artist, song.id]);
    if (log.length > _maxEntries) {
      log.removeRange(0, log.length - _maxEntries);
    }
    _cache = log;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(log));
  }

  /// 最近 7 天的每日播放次数（周一 → 周日）。
  Future<List<int>> weekCounts() async {
    final log = await _read();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final counts = List<int>.filled(7, 0);
    for (final e in log) {
      final ts = DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt());
      final day = DateTime(ts.year, ts.month, ts.day);
      final idx = day.difference(monday).inDays;
      if (idx >= 0 && idx < 7) counts[idx]++;
    }
    return counts;
  }

  /// 清空本地日志。
  Future<void> clear() async {
    _cache = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// 每首歌最近一次播放的时间（仅统计带歌曲 id 的新记录）。
  Future<Map<int, DateTime>> lastPlayedBySong() async {
    final log = await _read();
    final out = <int, DateTime>{};
    for (final e in log) {
      if (e.length < 3) continue;
      final id = (e[2] as num?)?.toInt();
      if (id == null) continue;
      final ts = DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt());
      final prev = out[id];
      if (prev == null || ts.isAfter(prev)) out[id] = ts;
    }
    return out;
  }

  /// 本周总播放次数 / 时长（秒）/ 最常听艺人。
  Future<({int plays, int seconds, String? topArtist})> weekSummary() async {
    final log = await _read();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    var plays = 0;
    final artists = <String, int>{};
    for (final e in log) {
      final ts = DateTime.fromMillisecondsSinceEpoch((e[0] as num).toInt());
      if (ts.isBefore(start)) continue;
      plays++;
      final a = (e.length > 1 ? e[1] as String? : null) ?? '';
      if (a.isNotEmpty) artists[a] = (artists[a] ?? 0) + 1;
    }
    String? top;
    var best = 0;
    artists.forEach((k, v) {
      if (v > best) {
        best = v;
        top = k;
      }
    });
    return (plays: plays, seconds: plays * 210, topArtist: top);
  }
}

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'common.dart';
import 'fn_icon.dart';

/// 信号链路节点。图标与 Web 端 `Icon.tsx` 同源。
class ChainNode {
  final FnIconName icon;
  final String title;
  final String? subtitle;
  final String state; // active / idle / warn
  ChainNode(this.icon, this.title, this.subtitle, this.state);
}

String _formatKhz(int? hz) {
  if (hz == null) return '?';
  return hz % 1000 == 0
      ? '${hz ~/ 1000}kHz'
      : '${(hz / 1000).toStringAsFixed(1)}kHz';
}

String _clientName() {
  try {
    if (Platform.isWindows) return 'Flutter App · Windows';
    if (Platform.isAndroid) return 'Flutter App · Android';
    if (Platform.isLinux) return 'Flutter App · Linux';
    if (Platform.isMacOS) return 'Flutter App · macOS';
    if (Platform.isIOS) return 'Flutter App · iOS';
  } catch (_) {}
  return 'Flutter App';
}

/// 与播放控制器的路由逻辑保持一致，推导完整信号链路。
List<ChainNode> buildSignalChain({
  required AppLocalizations l,
  required Song? song,
  required int? presetId,
  required String? presetName,
  required String quality,
  required String rgMode,
  required bool casting,
  required String? rendererName,
  required double volume,
  required bool muted,
}) {
  if (song == null) return [];
  final codec = song.codec ?? '?';
  final sr = _formatKhz(song.sampleRate);
  final bit = song.bitDepth != null ? '${song.bitDepth}bit' : null;
  final ch = song.channels != null ? '${song.channels}ch' : '?';
  final src = [codec, sr, bit, ch].where((e) => e != null).join(' · ');

  final serverProcessed = presetId != null || quality != 'lossless';

  // ReplayGain 节点
  final ChainNode rgNode;
  final rgSuffix = rgMode == 'album' ? l.rgAlbum : l.rgTrack;
  if (rgMode == 'off') {
    rgNode = ChainNode(FnIconName.rg, 'ReplayGain', l.rgNotEnabled, 'idle');
  } else {
    final db = rgMode == 'album'
        ? (song.rgAlbumGain ?? song.rgTrackGain)
        : song.rgTrackGain;
    final peak = rgMode == 'album'
        ? (song.rgAlbumPeak ?? song.rgTrackPeak)
        : song.rgTrackPeak;
    if (db == null) {
      rgNode = ChainNode(
          FnIconName.rg, 'ReplayGain · $rgSuffix', l.rgMissingTag, 'idle');
    } else {
      final g = PlayerController.rgGainFor(song, rgMode)!;
      final rawGain = math.pow(10, db / 20).toDouble();
      final capped = peak != null && peak > 0 && rawGain > 1 / peak;
      final sign = db > 0 ? '+' : '';
      rgNode = ChainNode(
        FnIconName.rg,
        'ReplayGain · $rgSuffix $sign${db.toStringAsFixed(2)} dB',
        '${l.rgLinearGain(g.toStringAsFixed(3))}'
            '${capped ? ' · ${l.rgPeakCap}' : ''}',
        capped ? 'warn' : 'active',
      );
    }
  }

  // 输出节点
  final ChainNode outNode;
  if (casting) {
    outNode = ChainNode(FnIconName.airplay, l.dlnaPush,
        '→ ${rendererName ?? l.rendererFallback}', 'active');
  } else if (serverProcessed) {
    final outLabel = switch (quality) {
      'cd' => 'FLAC 16 bit',
      'hd' => 'FLAC 24 bit',
      'high' => 'Opus 256 kbps',
      'standard' => 'Opus 128 kbps',
      'low' => 'Opus 64 kbps',
      _ => l.flacFollowSource,
    };
    outNode = ChainNode(
      FnIconName.codec,
      l.httpStream,
      l.outParams(outLabel),
      'active',
    );
  } else {
    outNode =
        ChainNode(FnIconName.codec, l.httpDirect, l.httpDirectSub, 'active');
  }

  return [
    ChainNode(FnIconName.music, l.sourceFile, src, 'active'),
    ChainNode(
        FnIconName.library, l.decodeToPcm(codec), l.symphoniaDecode, 'active'),
    serverProcessed
        ? ChainNode(
            FnIconName.dsp, l.resampleMix, l.resampleTarget(src), 'active')
        : ChainNode(
            FnIconName.dsp, l.resampleMix, l.resamplePassthrough, 'idle'),
    rgNode,
    presetId != null
        ? ChainNode(
            FnIconName.dsp,
            l.presetWithName(presetName ?? '#$presetId'),
            l.camillaDsp,
            'active')
        : ChainNode(FnIconName.dsp, l.playerFx, l.presetIdle, 'idle'),
    outNode,
    ChainNode(
        FnIconName.volume,
        muted ? l.volumeMuted : l.volumePercent((volume * 100).round()),
        l.clientVolume,
        muted ? 'idle' : 'active'),
    ChainNode(
        FnIconName.device,
        casting ? (rendererName ?? l.dlnaRenderer) : _clientName(),
        casting ? l.dlnaRendererOutput : l.clientAudioOut,
        'active'),
  ];
}

/// 弹出信号路径底部面板。
Future<void> openSignalPath(
  BuildContext context, {
  required List<DspPreset> presets,
}) {
  final c = PlayerController.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: FnColors.barrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return FnGlass(
        radius: 20,
        blur: 32,
        color: FnColors.material,
        child: StreamBuilder<void>(
          stream: c.stateChanges.stream,
          builder: (context, _) {
            final l = context.l10n;
            final song = c.current;
            String? name;
            for (final p in presets) {
              if (p.id == c.presetId) name = p.name;
            }
            final nodes = buildSignalChain(
              l: l,
              song: song,
              presetId: c.presetId,
              presetName: name,
              quality: c.quality,
              rgMode: c.rgMode,
              casting: c.isCasting,
              rendererName: c.dlnaRenderer?.name,
              volume: c.volume,
              muted: c.muted,
            );
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: FnSheetHandle()),
                    const SizedBox(height: 14),
                    Text(l.signalPathTitle,
                        style: TextStyle(
                            fontSize: 17,
                            color: FnColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    if (nodes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(l.notPlaying,
                            style: TextStyle(color: FnColors.textTertiary)),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < nodes.length; i++)
                                _ChainRow(
                                    node: nodes[i],
                                    isLast: i == nodes.length - 1),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _ChainRow extends StatelessWidget {
  final ChainNode node;
  final bool isLast;
  const _ChainRow({required this.node, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final idle = node.state == 'idle';
    final Color dot = node.state == 'active'
        ? FnColors.green
        : node.state == 'warn'
            ? FnColors.orange
            : FnColors.textTertiary;
    // 与 Web `.cp-ic` 一致：生效节点绿色描边 + 绿色图标，未启用节点灰描边。
    final Color accent = idle ? FnColors.textTertiary : FnColors.green;
    final Color circleBorder = idle ? FnColors.divider : FnColors.green;
    final Color circleBg =
        idle ? Colors.transparent : FnColors.green.withValues(alpha: 0.08);
    final titleColor =
        node.state == 'idle' ? FnColors.textSecondary : FnColors.textPrimary;
    final subColor =
        node.state == 'idle' ? FnColors.textTertiary : FnColors.textSecondary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: circleBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: circleBorder, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: FnIcon(node.icon, size: 17, color: accent),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: FnColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(node.title,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: node.state == 'idle'
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  color: titleColor,
                                  height: 1.3)),
                          if (node.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(node.subtitle!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                    height: 1.3)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 12, left: 8),
                    decoration:
                        BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

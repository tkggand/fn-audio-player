import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme.dart';
import 'common.dart';

/// 音质档位（5 档，文案与 Web 稿 / index.html 设置页一致）。
///
/// 映射同 Web：`cd` / `hd` 均为无损档，只是位深不同，流地址映射见
/// `ApiClient.qualityStreamParam` / `qualityBitDepth`。
Map<String, String> qualityOptions(AppLocalizations l) => <String, String>{
      'lossless': l.qualityLossless,
      'cd': l.qualityCd,
      'hd': l.qualityHd,
      'high': 'Opus · 256k',
      'standard': 'Opus · 128k',
    };

/// 音质档位显示文案。
String qualityLabel(BuildContext context, String q) {
  final l = context.l10n;
  return qualityOptions(l)[q] ?? l.qualityLossless;
}

/// 音质档位底部浮层（对齐 app.html「音质档位」浮层）。
///
/// 返回所选档位；未选择返回 null。
Future<String?> openQualitySheet(
  BuildContext context, {
  required String current,
}) {
  final l = context.l10n;
  final options = qualityOptions(l);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: FnColors.raisedHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (c) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const FnSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(l.qualityTierTitle,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
          for (final e in options.entries)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(c, e.key),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 16,
                          color: e.key == current
                              ? FnColors.primary
                              : FnColors.textPrimary,
                          fontWeight: e.key == current
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (e.key == current)
                      Icon(CupertinoIcons.checkmark,
                          size: 18, color: FnColors.limeText),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

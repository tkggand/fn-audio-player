import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoButton, CupertinoIcons;
import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../player_controller.dart';
import '../theme.dart';
import 'common.dart';

/// 播放设备选择（本机 / DLNA 渲染器）。
class DeviceMenu {
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: FnColors.barrier,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FnGlass(
        radius: 20,
        blur: 32,
        color: FnColors.material,
        child: const _DeviceSheet(),
      ),
    );
  }
}

class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet();

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  final controller = PlayerController.instance;
  final api = ApiClient.instance;

  List<DlnaRenderer> _renderers = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _renderers = await api.dlnaRenderers(refresh: refresh);
    } catch (e) {
      _error = '$e';
    }
    if (context.mounted) setState(() => _loading = false);
  }

  /// iOS 列表行：图标 + 主副标题 + 选中勾，最小高度 48。
  Widget _row({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 16, color: FnColors.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: FnColors.textSecondary)),
                ],
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark,
                  size: 18, color: FnColors.limeText),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
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
              child: Text(l.chooseDevice,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),
          _row(
            icon: CupertinoIcons.device_phone_portrait,
            iconColor: controller.isCasting
                ? FnColors.textSecondary
                : FnColors.primary,
            title: l.localPlayback,
            selected: !controller.isCasting,
            onTap: () async {
              if (controller.isCasting) {
                await controller.backToLocal();
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
          Container(height: 1, color: FnColors.divider),
          if (_loading && _renderers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CupertinoActivityIndicator(),
            ),
          if (!_loading || _renderers.isNotEmpty)
            for (final r in _renderers)
              _row(
                icon: CupertinoIcons.hifispeaker,
                iconColor: controller.dlnaRenderer?.id == r.id
                    ? FnColors.primary
                    : FnColors.textSecondary,
                title: r.name,
                subtitle: l.dlnaRenderer,
                selected: controller.dlnaRenderer?.id == r.id,
                onTap: () async {
                  if (controller.current == null) {
                    Navigator.pop(context);
                    return;
                  }
                  try {
                    await controller.castTo(r);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.castFailed('$e'))),
                      );
                    }
                  }
                  if (context.mounted) Navigator.pop(context);
                },
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.scanFailed('$_error'),
                  style: TextStyle(color: FnColors.red)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  onPressed: () => _scan(refresh: true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.arrow_counterclockwise,
                          size: 18, color: FnColors.limeText),
                      const SizedBox(width: 6),
                      Text(l.rescan,
                          style: TextStyle(
                              fontSize: 15, color: FnColors.limeText)),
                    ],
                  ),
                ),
                if (controller.isCasting)
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    onPressed: () async {
                      await controller.backToLocal();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.tv_fill,
                            size: 18, color: FnColors.limeText),
                        const SizedBox(width: 6),
                        Text(l.castedTo(controller.dlnaRenderer?.name ?? ''),
                            style: TextStyle(
                                fontSize: 15, color: FnColors.limeText)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

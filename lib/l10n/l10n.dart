import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';
export 'locale_controller.dart';

/// 页面取文案的统一入口：`context.l10n.meTitle`。
extension FnL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// 服务器地址校验错误码（`ApiClient.normalizeBaseUrl` 抛出）→ 本地化文案。
String serverUrlErrorText(AppLocalizations l, String code) => switch (code) {
      'empty' => l.serverUrlEmpty,
      'scheme' => l.serverUrlScheme,
      _ => l.serverUrlHost,
    };

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/l10n/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/ui/theme/app_theme.dart';
import 'features/notifications/presentation/in_app_banner.dart';
import 'features/notifications/presentation/notifications_providers.dart';

class KApp extends ConsumerWidget {
  const KApp({super.key, this.locale});

  /// Forces a locale (tests); otherwise the user's saved choice, falling back
  /// to the device locale.
  final Locale? locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Registers this device for push and opens tapped pushes (F07).
    ref.watch(pushControllerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(),
      locale: locale ?? ref.watch(localeControllerProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          InAppBannerHost(child: child ?? const SizedBox.shrink()),
    );
  }
}

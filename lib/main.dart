import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/bootstrap.dart';
import 'core/l10n/locale_store.dart';
import 'features/onboarding/data/onboarding_store.dart';
import 'features/storefront/data/recent_search_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  await bootstrap(config);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        localeStoreProvider.overrideWithValue(SharedPrefsLocaleStore(prefs)),
        onboardingStoreProvider.overrideWithValue(
          SharedPrefsOnboardingStore(prefs),
        ),
        recentSearchStoreProvider.overrideWithValue(
          SharedPrefsRecentSearchStore(prefs),
        ),
      ],
      child: const KApp(),
    ),
  );
}

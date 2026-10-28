import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/ui/theme/app_theme.dart';
import 'package:k_e_commerce/features/onboarding/data/onboarding_store.dart';

/// A device that has already been through first launch (S-02, S-03), for
/// tests that pump the whole app and expect to land on a home.
final onboardedDevice = onboardingStoreProvider.overrideWithValue(
  MemoryOnboardingStore.done(),
);

/// The storefront home (C-01 / B-00) of the `customer` or `business` shell.
Finder storeHome(String role) => find.byKey(ValueKey('store-home-$role'));

/// Text on the back-office dashboard (A-01) until its task builds it.
const adminHome = 'This screen (A-01) arrives in a later update.';

/// Wraps [child] in a MaterialApp with the app's theme and localizations.
Widget localized(Widget child, {Locale locale = const Locale('en')}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// [child] on a K page background, for component tests and goldens.
Widget kHarness(
  Widget child, {
  Locale locale = const Locale('en'),
  double width = 390,
}) {
  return localized(
    Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
    locale: locale,
  );
}

/// Runs [body] with real soft shadows; flutter_test draws them solid by
/// default and checks the flag is restored before tear-down.
Future<void> withRealShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Sizes the test view in logical pixels at 1x.
void setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/money/khr_rate_provider.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';

class _FixedRate implements SettingsRepository {
  const _FixedRate(this.rate);

  final int rate;

  @override
  Future<int?> khrPerUsd() async => rate;
}

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('shows USD and KHR at the default rate', (tester) async {
    await tester.pumpWidget(_app(const KPrice(cents: 4900)));
    await tester.pumpAndSettle();
    expect(find.text(r'$49.00'), findsOneWidget);
    expect(find.text('≈ KHR 200,900'), findsOneWidget);
  });

  testWidgets('uses the rate from settings', (tester) async {
    await tester.pumpWidget(
      _app(
        const KPrice(cents: 4900, size: KPriceSize.md),
        overrides: [
          settingsRepositoryProvider.overrideWithValue(const _FixedRate(4000)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('≈ KHR 196,000'), findsOneWidget);
  });

  testWidgets('Khmer wording, same figures', (tester) async {
    await tester.pumpWidget(
      _app(const KPrice(cents: 4900), locale: const Locale('km')),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$49.00'), findsOneWidget);
    expect(find.text('≈ 200,900 រៀល'), findsOneWidget);
  });

  testWidgets('USD only when KHR is hidden', (tester) async {
    await tester.pumpWidget(_app(const KPrice(cents: 4900, showKhr: false)));
    expect(find.textContaining('KHR'), findsNothing);
  });

  testWidgets('figures are tabular', (tester) async {
    await tester.pumpWidget(_app(const KPrice(cents: 4900)));
    final usd = tester.widget<Text>(find.text(r'$49.00'));
    expect(
      usd.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });
}

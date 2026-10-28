import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/l10n/locale_controller.dart';
import 'package:k_e_commerce/core/l10n/locale_store.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/settings/presentation/language_select_view.dart';

import '../../helpers.dart';
import '../storefront/fakes.dart';

/// An app whose language follows [localeControllerProvider], like [KApp].
class _LiveApp extends ConsumerWidget {
  const _LiveApp(this.home);

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: AppTheme.light(),
    locale: ref.watch(localeControllerProvider) ?? const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}

void main() {
  group('Account language sheet (S-08c)', () {
    testWidgets('saving Khmer switches every string live and is kept', (
      tester,
    ) async {
      final store = MemoryLocaleStore('en');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeStoreProvider.overrideWithValue(store),
            onboardedDevice,
            // Home's best sellers show one $49.00 card.
            ...storefrontOverrides(
              FakeStorefrontRepository(products: const [headphonesPro]),
            ),
          ],
          child: const KApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(storeHome('customer'), findsOneWidget);
      expect(find.text('≈ KHR 200,900'), findsOneWidget);

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      expect(find.text('App language'), findsNothing); // a11y label only
      expect(find.text('Current language'), findsOneWidget);
      expect(find.text('ខ្មែរ'), findsOneWidget);

      await tester.tap(find.text('Khmer'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('គណនី'), findsWidgets); // Account title and tab
      expect(find.text('ភាសា'), findsOneWidget);
      await tester.tap(find.text('ទំព័រដើម'));
      await tester.pumpAndSettle();
      expect(find.text('ទិញតាមប្រភេទ'), findsOneWidget);
      expect(find.text(r'$49.00'), findsOneWidget);
      expect(find.text('≈ 200,900 រៀល'), findsOneWidget);
      expect(store.read(), 'km');
    });

    testWidgets('closing without saving keeps the language', (tester) async {
      final store = MemoryLocaleStore('en');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localeStoreProvider.overrideWithValue(store),
            onboardedDevice,
          ],
          child: const KApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khmer'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Account'), findsWidgets);
      expect(find.text('English'), findsOneWidget); // the row's value
      expect(store.read(), 'en');
    });
  });

  group('Choose language (S-02)', () {
    testWidgets('picking a card previews the language at once', (tester) async {
      var continued = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: _LiveApp(LanguageSelectView(onContinue: () => continued++)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose your language'), findsOneWidget);

      await tester.tap(find.text('Khmer'));
      await tester.pumpAndSettle();
      expect(find.text('ជ្រើសរើសភាសារបស់អ្នក'), findsOneWidget);

      await tester.tap(find.text('បន្ត'));
      expect(continued, 1);
    });

    testWidgets('rows are radio buttons at least 44 px tall', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(child: _LiveApp(LanguageSelectView(onContinue: () {}))),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('English')),
        isSemantics(
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: true,
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('Khmer')),
        isSemantics(isChecked: false, label: 'Khmer\nខ្មែរ'),
      );
      expect(
        tester.getSize(find.byType(InkWell).first).height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });
  });
}

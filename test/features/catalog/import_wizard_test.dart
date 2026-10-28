import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/catalog/domain/csv_import.dart';
import 'package:k_e_commerce/features/catalog/presentation/import_wizard.dart';

import '../admin/admin_harness.dart';
import '../auth/auth_harness.dart' show settleToasts;
import 'fakes.dart';

const _csv =
    'name,name_km,sku,price_usd,qty,category,supplier_code\n'
    'Studio Monitor,,MON-BLK,129,8,audio,S-1\n'
    'Kettle,កំសៀវ,KET-1,12.50,,kitchen,S-2\n'
    'Mug copy,,MUG-4-SND,5,1,kitchen,S-3\n';

Finder _button(String label) => find.widgetWithText(KButton, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<KButton>(_button(label)).onPressed != null;

void main() {
  setUpAll(initializeDateFormatting);

  group('A-05d import products', () {
    testWidgets('upload, match columns, review errors, import', (tester) async {
      final repo = FakeCatalogRepository();
      final picker = FakeFilePicker()
        ..next = [(name: 'products_oct.csv', bytes: utf8.encode(_csv))];
      await pumpAdmin(
        tester,
        email: 'visal@kstore.example',
        location: AppRoutes.adminCatalog,
        overrides: catalogOverrides(repo, picker: picker),
      );
      await tester.tap(_button('Import CSV'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportWizard), findsOneWidget);
      expect(find.text('Import products'), findsOneWidget);

      await tester.tap(_button('Choose a CSV file'));
      await tester.pumpAndSettle();
      expect(picker.asked.single, ['csv']);
      expect(find.text('products_oct.csv'), findsOneWidget);
      expect(find.text('3 rows · 7 columns'), findsOneWidget);
      expect(find.text('(empty in 2 rows)'), findsOneWidget);
      // Template columns are matched; the supplier code is left out.
      expect(find.text('Price (USD, incl. VAT)'), findsOneWidget);
      expect(find.text("Don't import"), findsOneWidget);

      await tester.tap(_button('Check rows'));
      await tester.pumpAndSettle();
      final (action, csv, mapping) = repo.imports.single;
      expect(action, 'preview');
      expect(csv, _csv);
      expect(mapping['supplier_code'], ImportField.ignore);
      expect(mapping['price_usd'], ImportField.priceUsd);
      expect(find.text('1 row has errors and will be skipped'), findsOneWidget);
      expect(
        find.text('Row 5: SKU "MUG-4-SND" already exists'),
        findsOneWidget,
      );
      expect(find.text('They make 2 products.'), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(_button('Error report'));
      await tester.pumpAndSettle();
      expect(find.text('Error report copied.'), findsOneWidget);
      expect(copied, 'Row 5: SKU "MUG-4-SND" already exists');
      // The toast sits over the footer until it goes.
      await settleToasts(tester);

      await tester.tap(_button('Continue with 3 rows'));
      await tester.pumpAndSettle();
      expect(repo.imports.last.$1, 'commit');
      expect(find.byType(ImportWizard), findsNothing);
      expect(
        find.text(
          '2 products imported as drafts. Add images and set them active when ready.',
        ),
        findsOneWidget,
      );
      await settleToasts(tester);
    });

    testWidgets('every required field needs a column', (tester) async {
      final repo = FakeCatalogRepository();
      final picker = FakeFilePicker()
        ..next = [(name: 'a.csv', bytes: utf8.encode('title,code\nMug,M-1\n'))];
      await pumpAdmin(
        tester,
        email: 'chenda@kstore.example',
        location: AppRoutes.adminCatalog,
        overrides: catalogOverrides(repo, picker: picker),
      );
      await tester.tap(_button('Import CSV'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Choose a CSV file'));
      await tester.pumpAndSettle();
      expect(
        find.text('Match a column to: Price (USD, incl. VAT), Category'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Check rows'), isFalse);
      expect(repo.imports, isEmpty);
    });

    testWidgets('empty and oversized files are refused', (tester) async {
      final repo = FakeCatalogRepository();
      final picker = FakeFilePicker()
        ..next = [(name: 'a.csv', bytes: utf8.encode('name,sku\n'))];
      await pumpAdmin(
        tester,
        email: 'visal@kstore.example',
        location: AppRoutes.adminCatalog,
        overrides: catalogOverrides(repo, picker: picker),
      );
      await tester.tap(_button('Import CSV'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Choose a CSV file'));
      await tester.pumpAndSettle();
      expect(find.text('The file has no rows.'), findsOneWidget);

      picker.next = [(name: 'b.csv', bytes: Uint8List(maxImportBytes + 1))];
      await tester.tap(_button('Choose a CSV file'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The file is too big. Import up to 5,000 rows (2 MB) at a time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('phones get the wizard as a page', (tester) async {
      final container = await pumpAdmin(
        tester,
        email: 'visal@kstore.example',
        size: phone,
        location: AppRoutes.adminCatalog,
        overrides: catalogOverrides(FakeCatalogRepository()),
      );
      await tester.tap(_button('Import CSV'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportWizardPage), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        AppRoutes.adminCatalog,
      );
    });
  });
}

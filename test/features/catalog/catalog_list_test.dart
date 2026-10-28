import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_list.dart';
import 'package:k_e_commerce/features/catalog/presentation/catalog_list_page.dart';
import 'package:k_e_commerce/features/catalog/presentation/product_editor_page.dart';

import '../admin/admin_harness.dart';
import '../auth/auth_harness.dart' show settleToasts;
import 'fakes.dart';

Future<FakeCatalogRepository> _openList(
  WidgetTester tester, {
  String email = 'visal@kstore.example',
  Size size = desktop,
  FakeCatalogRepository? catalog,
}) async {
  final repo = catalog ?? FakeCatalogRepository();
  await pumpAdmin(
    tester,
    email: email,
    size: size,
    location: AppRoutes.adminCatalog,
    overrides: catalogOverrides(repo),
  );
  return repo;
}

Finder _checkbox(String label) => find.bySemanticsLabel(label);

final _search = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Search name or SKU',
);

void main() {
  setUpAll(initializeDateFormatting);

  group('A-05 products', () {
    testWidgets('lists products with tabs, counts and the A-05 pills', (
      tester,
    ) async {
      await _openList(tester);
      expect(find.byType(CatalogListPage), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
      expect(find.text('P-HP-1 · Sonora'), findsOneWidget);
      expect(find.text('52 · 1 out'), findsOneWidget);
      expect(find.text('Min 5'), findsOneWidget);
      // The pill and the Stock filter chip.
      expect(find.text('Out of stock'), findsNWidgets(2));
      expect(find.text('Not stocked'), findsOneWidget);
      expect(find.text(r'$49.00'), findsOneWidget);
      // "All" leaves archived products out.
      expect(find.text('Old Speaker'), findsNothing);
      expect(find.text('Showing 4 of 4'), findsOneWidget);
      expect(find.text('Import CSV'), findsOneWidget);
      expect(find.text('Add product'), findsOneWidget);
    });

    testWidgets('tabs, search and filters narrow the list', (tester) async {
      final repo = await _openList(tester);
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Old Speaker'), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quote enabled'));
      await tester.pumpAndSettle();
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
      expect(find.text('Bluetooth Speaker Mini'), findsNothing);
      expect(repo.queries.last.quoteOnly, isTrue);

      await tester.tap(find.text('Quote enabled'));
      await tester.enterText(_search, 'mug');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.queries.last.search, 'mug');
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsNothing);

      await tester.enterText(_search, 'nothing like this');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No products here'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
    });

    testWidgets('filters by category from the picker', (tester) async {
      final repo = await _openList(tester);
      await tester.tap(find.text('Category: All categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen').last);
      await tester.pumpAndSettle();
      expect(repo.queries.last.categoryId, 'c-kitchen');
      expect(find.text('No products here'), findsOneWidget);
      expect(find.text('Category: Kitchen'), findsOneWidget);
    });

    testWidgets('bulk archive asks first, then archives the selection', (
      tester,
    ) async {
      final repo = await _openList(tester);
      await tester.tap(_checkbox('Select Wireless Headphones Pro'));
      await tester.tap(_checkbox('Select Ceramic Coffee Mug Set'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Archive 2 products?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive products'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['archive p-hp,p-mug']);
      expect(find.text('2 products archived.'), findsOneWidget);
      expect(find.text('2 selected'), findsNothing);
      await settleToasts(tester);
    });

    testWidgets('moves the selection to another category', (tester) async {
      final repo = await _openList(tester);
      await tester.tap(_checkbox('Select all on this page'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected'), findsOneWidget);
      await tester.tap(find.text('Change category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitchen').last);
      await tester.pumpAndSettle();
      expect(repo.calls, ['move p-hp,p-mug,p-spk,p-rice c-kitchen']);
      expect(find.text('4 products moved to Kitchen.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('pages through long lists', (tester) async {
      final repo = FakeCatalogRepository(
        rows: [for (var i = 0; i < 30; i++) listItem('p-$i', 'Product $i')],
      );
      await _openList(tester, catalog: repo);
      expect(find.text('1–25 of 30'), findsOneWidget);
      final next = find.byWidgetPredicate(
        (w) => w is KIconButton && w.label == 'Next page',
      );
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('26–30 of 30'), findsOneWidget);
      expect(find.text('Product 29'), findsOneWidget);
    });

    testWidgets('Edit opens the product', (tester) async {
      await _openList(tester);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      expect(find.byType(ProductEditorPage), findsOneWidget);
    });

    testWidgets('sales can look but not change anything', (tester) async {
      await _openList(tester, email: 'dalin@kstore.example');
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
      expect(
        find.text(
          'You can view products. Only catalog staff and super admins can change them.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add product'), findsNothing);
      expect(find.text('Import CSV'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('View'), findsWidgets);
    });

    testWidgets('phones get cards', (tester) async {
      await _openList(tester, size: phone);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
      expect(find.text(r'$49.00'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final repo = _FailingCatalog();
      await _openList(tester, catalog: repo);
      expect(find.text("Couldn't load products."), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
    });
  });
}

class _FailingCatalog extends FakeCatalogRepository {
  var fail = true;

  @override
  Future<CatalogPage> list(CatalogListQuery query) async {
    if (fail) throw StateError('offline');
    return super.list(query);
  }
}

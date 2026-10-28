import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/inventory/domain/inventory.dart';
import 'package:k_e_commerce/features/inventory/presentation/inventory_list_page.dart';

import '../admin/admin_harness.dart';
import 'fakes.dart';

Future<FakeInventoryRepository> openInventory(
  WidgetTester tester, {
  String email = 'visal@kstore.example',
  Size size = desktop,
  FakeInventoryRepository? inventory,
}) async {
  final repo = inventory ?? FakeInventoryRepository();
  await pumpAdmin(
    tester,
    email: email,
    size: size,
    location: AppRoutes.adminInventory,
    overrides: inventoryOverrides(repo),
  );
  return repo;
}

final _search = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Search product or SKU',
);

void main() {
  setUpAll(initializeDateFormatting);

  group('A-06 inventory', () {
    testWidgets('summary tiles and the needs-restock list', (tester) async {
      final repo = await openInventory(tester);
      expect(find.byType(InventoryListPage), findsOneWidget);
      expect(find.text('Catalog · Phnom Penh store'), findsOneWidget);

      // Tiles: 2 low, 1 out, 2 reserved, stock value in whole dollars.
      expect(find.text('Below their alert level'), findsOneWidget);
      expect(find.text('Units in unpaid or packing orders'), findsOneWidget);
      expect(find.text(r'$48,210'), findsOneWidget);

      // Needs restock is the default: low and out only.
      expect(repo.queries.last.filter, InventoryFilter.restock);
      expect(find.text('LMP-LED-WHT'), findsOneWidget);
      expect(find.text('HP-PRO-SKY'), findsOneWidget);
      expect(find.text('SW-ACT2-BLK'), findsNothing);
      expect(find.text('LED Desk Lamp · White'), findsOneWidget);
      expect(find.text('Low'), findsNWidgets(2));
      expect(find.text('Out'), findsOneWidget);

      // Last change: what happened and who or which order.
      expect(find.text('Sold −2'), findsOneWidget);
      expect(find.textContaining('Order K-10253'), findsOneWidget);
      expect(
        find.text('3 SKUs need restocking · alert levels are set per variant'),
        findsOneWidget,
      );
      expect(
        find.text('Reserved stock is released after 15 min if KHQR isn’t paid'),
        findsOneWidget,
      );
      expect(find.text('Adjust'), findsNWidgets(3));
      expect(find.text('Adjust stock'), findsOneWidget);
    });

    testWidgets('filters and search go to the server', (tester) async {
      final repo = await openInventory(tester);

      await tester.tap(find.text('All SKUs'));
      await tester.pumpAndSettle();
      expect(repo.queries.last.filter, InventoryFilter.all);
      expect(find.text('SW-ACT2-BLK'), findsOneWidget);
      expect(find.text('Not stocked'), findsOneWidget);
      expect(find.text('Count correction'), findsNothing);
      expect(find.text('Adjusted −1'), findsOneWidget);

      await tester.tap(find.text('Out of stock').last);
      await tester.pumpAndSettle();
      expect(repo.queries.last.filter, InventoryFilter.out);
      expect(find.text('HP-PRO-SKY'), findsOneWidget);
      expect(find.text('LMP-LED-WHT'), findsNothing);

      await tester.enterText(_search, 'lamp');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.queries.last.search, 'lamp');
      expect(repo.queries.last.page, 0);
      expect(find.text('No SKUs here'), findsOneWidget);

      await tester.tap(find.text('Show all SKUs'));
      await tester.pumpAndSettle();
      expect(repo.queries.last.filter, InventoryFilter.all);
      expect(repo.queries.last.search, '');
    });

    testWidgets('support can look but not adjust', (tester) async {
      await openInventory(tester, email: 'sophea@kstore.example');
      expect(find.text('LMP-LED-WHT'), findsOneWidget);
      expect(
        find.text(
          'You can view stock. Only catalog staff and super admins can adjust it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Adjust'), findsNothing);
      expect(find.text('Adjust stock'), findsNothing);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final repo = FakeInventoryRepository()..failList = true;
      await openInventory(tester, inventory: repo);
      expect(find.text('Couldn’t load inventory'), findsOneWidget);

      repo.failList = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('LMP-LED-WHT'), findsOneWidget);
    });

    testWidgets('phones get one card per SKU', (tester) async {
      await openInventory(tester, size: phone);
      expect(find.text('On hand 4 · Reserved 1 · Available 3'), findsOneWidget);
      expect(find.text('LMP-LED-WHT'), findsOneWidget);
      expect(find.text('Adjust'), findsNWidgets(3));
    });

    testWidgets('the adjustment history sheet lists every movement', (
      tester,
    ) async {
      await openInventory(tester);
      await tester.tap(find.text('View adjustment history'));
      await tester.pumpAndSettle();
      expect(find.text('Adjustment history'), findsOneWidget);
      expect(find.text('LMP-LED-WHT · Received +50 · DN-2210'), findsOneWidget);
      expect(find.text('LMP-LED-WHT · Held for order −1'), findsOneWidget);
      expect(find.text('27 Oct, 8:00 AM · Visal Keo'), findsOneWidget);
    });
  });
}

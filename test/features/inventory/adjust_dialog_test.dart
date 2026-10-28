import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/features/inventory/domain/inventory.dart';

import '../admin/admin_harness.dart';
import '../auth/auth_harness.dart' show settleToasts;
import 'inventory_page_test.dart' show openInventory;

final _note = find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'For example, the delivery note number',
);

/// The A-06a quantity box, whatever the mode calls it.
final _qty = find.byWidgetPredicate(
  (w) => w is TextField && w.keyboardType == TextInputType.number,
);

Future<void> _openLampDialog(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Adjust').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Adjust').first);
  await tester.pumpAndSettle();
  expect(find.text('LMP-LED-WHT · On hand 4 · Reserved 1'), findsOneWidget);
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save adjustment'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save adjustment'));
}

Future<void> _saveAndConfirm(WidgetTester tester) async {
  await _tapSave(tester);
  await tester.pumpAndSettle();
  expect(find.text('Save this adjustment?'), findsOneWidget);
  await tester.tap(find.text('Save adjustment').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initializeDateFormatting);

  group('A-06a adjust stock', () {
    testWidgets('adding a delivery: preview, confirm, save and refresh', (
      tester,
    ) async {
      final repo = await openInventory(tester);
      final listCalls = repo.queries.length;
      await _openLampDialog(tester);

      expect(find.text('Add stock'), findsOneWidget);
      expect(
        find.text('New delivery or items returned to stock'),
        findsOneWidget,
      );
      expect(
        find.text('Saved to the audit log under your name.'),
        findsOneWidget,
      );
      // Recent changes of this SKU.
      expect(find.text('Received +50 · DN-2210'), findsOneWidget);

      await tester.enterText(_qty, '50');
      await tester.enterText(_note, 'Delivery note DN-2210 from supplier');
      await tester.pump();
      expect(find.text('54'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'LMP-LED-WHT: on hand goes from 4 to 54. Received from supplier.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save adjustment').last);
      await tester.pumpAndSettle();

      final (adjustment, label) = repo.adjustments.single;
      expect(adjustment.toPayload(reasonLabel: label), {
        'action': 'adjust',
        'variant_id': 'v-LMP-LED-WHT',
        'mode': 'add',
        'qty': 50,
        'reason': 'received',
        'note': 'Delivery note DN-2210 from supplier',
      });
      expect(
        find.text('Stock updated. LMP-LED-WHT now has 54 on hand.'),
        findsOneWidget,
      );
      expect(find.text('Adjust stock'), findsOneWidget); // dialog closed
      expect(repo.queries.length, greaterThan(listCalls));
      await settleToasts(tester);
    });

    testWidgets('cancelling the confirmation saves nothing', (tester) async {
      final repo = await openInventory(tester);
      await _openLampDialog(tester);
      await tester.enterText(_qty, '5');
      await tester.pump();
      await _tapSave(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(repo.adjustments, isEmpty);
      expect(find.text('LMP-LED-WHT · On hand 4 · Reserved 1'), findsOneWidget);
    });

    testWidgets('removing more than open orders allow is blocked', (
      tester,
    ) async {
      final repo = await openInventory(tester);
      await _openLampDialog(tester);

      await tester.tap(find.text('Remove stock'));
      await tester.pump();
      expect(find.text('Quantity to remove'), findsOneWidget);
      // Remove offers only removal reasons; Damaged is picked.
      expect(find.text('Received from supplier'), findsNothing);
      expect(find.text('Lost'), findsOneWidget);

      await tester.enterText(_qty, '4');
      await tester.pump();
      expect(
        find.text(
          '1 unit is held for an open order, so on hand can’t go below 1.',
        ),
        findsOneWidget,
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('Save this adjustment?'), findsNothing);

      await tester.enterText(_qty, '2');
      await tester.tap(find.text('Lost'));
      await tester.pump();
      expect(find.text('Out'), findsWidgets);
      await _saveAndConfirm(tester);

      final (adjustment, label) = repo.adjustments.single;
      expect(adjustment.toPayload(reasonLabel: label)['reason'], 'adjustment');
      expect(adjustment.toPayload(reasonLabel: label)['note'], 'Lost');
      await settleToasts(tester);
    });

    testWidgets('a stock count sets the exact number', (tester) async {
      final repo = await openInventory(tester);
      await _openLampDialog(tester);

      await tester.tap(find.text('Set exact count'));
      await tester.pump();
      expect(find.text('Counted on hand'), findsOneWidget);
      await tester.enterText(_qty, '4');
      await tester.pump();
      expect(find.text('This leaves on hand as it is.'), findsOneWidget);

      await tester.enterText(_qty, '7');
      await tester.pump();
      await _saveAndConfirm(tester);
      final (adjustment, _) = repo.adjustments.single;
      expect(adjustment.mode, AdjustMode.set);
      expect(adjustment.qty, 7);
      expect(adjustment.reason, AdjustReason.countCorrection);
      await settleToasts(tester);
    });

    testWidgets('a server refusal stays in the dialog', (tester) async {
      final repo = await openInventory(tester)
        ..next = const StockBelowReserved(3);
      await _openLampDialog(tester);
      await tester.enterText(_qty, '1');
      await tester.pump();
      await _saveAndConfirm(tester);

      expect(
        find.text(
          '3 units are held for open orders, so on hand can’t go below 3.',
        ),
        findsOneWidget,
      );
      expect(find.text('LMP-LED-WHT · On hand 4 · Reserved 1'), findsOneWidget);
      expect(repo.adjustments, hasLength(1));
    });

    testWidgets('Adjust stock in the page head picks a SKU first', (
      tester,
    ) async {
      await openInventory(tester);
      await tester.tap(find.text('Adjust stock'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a SKU'), findsOneWidget);
      await tester.tap(find.text('Smart Watch Active 2 · Black'));
      await tester.pumpAndSettle();
      expect(
        find.text('SW-ACT2-BLK · On hand 58 · Reserved 0'),
        findsOneWidget,
      );
    });

    testWidgets('works as a sheet on phones', (tester) async {
      await openInventory(tester, size: phone);
      await _openLampDialog(tester);
      expect(find.text('Add stock'), findsOneWidget);
      expect(find.text('Save adjustment'), findsOneWidget);
    });
  });
}

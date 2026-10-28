import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/money/money_format.dart';
import 'package:k_e_commerce/features/inventory/domain/inventory.dart';

void main() {
  group('stock state', () {
    test(
      'available at or under the alert level is low; nothing left is out',
      () {
        expect(
          InventoryState.of(available: 0, alertAt: 10),
          InventoryState.out,
        );
        expect(
          InventoryState.of(available: -1, alertAt: 10),
          InventoryState.out,
        );
        expect(
          InventoryState.of(available: 10, alertAt: 10),
          InventoryState.low,
        );
        expect(
          InventoryState.of(available: 11, alertAt: 10),
          InventoryState.ok,
        );
        expect(InventoryState.of(available: 1, alertAt: 0), InventoryState.ok);
      },
    );

    test('rows read the RPC shape; available = on hand − reserved', () {
      final row = InventoryRow.fromRow({
        'variant_id': 'v1',
        'product_id': 'p1',
        'sku': 'LMP-LED-WHT',
        'name': {'en': 'LED Desk Lamp'},
        'attributes': {'size': 'L', 'colour': 'White'},
        'main_image': 'products/a.jpg',
        'on_hand': 4,
        'reserved': 1,
        'alert_at': 10,
        'state': 'low',
        'last': {
          'reason': 'sold',
          'delta': -2,
          'at': '2026-10-27T03:24:00Z',
          'order_number': 'K-10253',
        },
      }, imageUrl: (p) => p == null ? null : 'https://img/$p');
      expect(row.available, 3);
      expect(row.state, InventoryState.low);
      expect(row.variantLabel, 'White / L');
      expect(row.mainImageUrl, 'https://img/products/a.jpg');
      expect(row.last!.reason, StockReason.sold);
      expect(row.last!.orderNumber, 'K-10253');
    });

    test('summary and counts tolerate missing keys', () {
      final summary = InventorySummary.fromJson({'low': 5, 'out': 3});
      expect(summary.reservedUnits, 0);
      expect(InventoryPage.countsFromJson({'restock': 8, 'all': 40}), {
        InventoryFilter.restock: 8,
        InventoryFilter.all: 40,
      });
      expect(InventoryFilter.fromWire('nope'), InventoryFilter.restock);
    });
  });

  group('A-06a form', () {
    test('the preview follows the mode', () {
      expect(onHandAfter(AdjustMode.add, 4, 50), 54);
      expect(onHandAfter(AdjustMode.remove, 4, 3), 1);
      expect(onHandAfter(AdjustMode.set, 4, 9), 9);
      expect(onHandAfter(AdjustMode.add, 4, null), isNull);
    });

    test('a count can never drop below what orders hold', () {
      AdjustProblem? check(AdjustMode mode, int? qty) =>
          adjustProblem(mode: mode, onHand: 4, reserved: 1, qty: qty);
      expect(check(AdjustMode.add, null), AdjustProblem.qtyRequired);
      expect(check(AdjustMode.add, 0), AdjustProblem.qtyRequired);
      expect(check(AdjustMode.add, 100001), AdjustProblem.qtyTooLarge);
      expect(check(AdjustMode.remove, 4), AdjustProblem.belowReserved);
      expect(check(AdjustMode.remove, 3), isNull);
      expect(check(AdjustMode.set, 0), AdjustProblem.belowReserved);
      expect(check(AdjustMode.set, 4), AdjustProblem.noChange);
      expect(check(AdjustMode.set, 1), isNull);
    });

    test('each mode offers its own reasons, mapped to the ledger', () {
      expect(AdjustReason.forMode(AdjustMode.add), [
        AdjustReason.receivedFromSupplier,
        AdjustReason.returnedToStock,
        AdjustReason.countCorrection,
      ]);
      expect(AdjustReason.forMode(AdjustMode.remove), [
        AdjustReason.damaged,
        AdjustReason.lost,
        AdjustReason.usedInStore,
        AdjustReason.countCorrection,
      ]);
      expect(AdjustReason.forMode(AdjustMode.set), [
        AdjustReason.countCorrection,
      ]);
      for (final mode in AdjustMode.values) {
        expect(AdjustReason.defaultFor(mode).modes, contains(mode));
      }
      expect(AdjustReason.lost.wire, StockReason.adjustment);
      expect(AdjustReason.returnedToStock.wire, StockReason.returned);
    });

    test('the payload keeps labels the ledger cannot tell apart', () {
      const lost = StockAdjustment(
        variantId: 'v1',
        mode: AdjustMode.remove,
        qty: 2,
        reason: AdjustReason.lost,
        note: '  back room ',
      );
      expect(lost.toPayload(reasonLabel: 'Lost'), {
        'action': 'adjust',
        'variant_id': 'v1',
        'mode': 'remove',
        'qty': 2,
        'reason': 'adjustment',
        'note': 'Lost · back room',
      });
      const received = StockAdjustment(
        variantId: 'v1',
        mode: AdjustMode.add,
        qty: 50,
        reason: AdjustReason.receivedFromSupplier,
      );
      expect(received.toPayload(reasonLabel: 'Received from supplier'), {
        'action': 'adjust',
        'variant_id': 'v1',
        'mode': 'add',
        'qty': 50,
        'reason': 'received',
      });
    });

    test('inventory-manage answers', () {
      final adjusted = InventoryOutcome.fromJson({
        'status': 'adjusted',
        'on_hand': 54,
        'reserved': 1,
        'delta': 50,
      });
      expect(
        adjusted,
        isA<StockAdjusted>().having((o) => o.onHand, 'on hand', 54),
      );
      expect(
        InventoryOutcome.fromJson({'status': 'below_reserved', 'reserved': 2}),
        isA<StockBelowReserved>().having((o) => o.reserved, 'reserved', 2),
      );
      for (final (wire, reason) in [
        ('invalid', InventoryRefusal.invalid),
        ('not_found', InventoryRefusal.notFound),
        ('forbidden', InventoryRefusal.forbidden),
        ('weird', InventoryRefusal.unknown),
      ]) {
        expect(
          InventoryOutcome.fromJson({'status': wire}),
          isA<InventoryRefused>().having((o) => o.reason, 'reason', reason),
        );
      }
    });
  });

  test('stock value in whole dollars', () {
    expect(formatUsdWhole(4821049), r'$48,210');
    expect(formatUsdWhole(4821050), r'$48,211');
    expect(formatUsdWhole(0), r'$0');
  });
}

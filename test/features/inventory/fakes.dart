import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/inventory/data/inventory_repository.dart';
import 'package:k_e_commerce/features/inventory/domain/inventory.dart';

import '../admin/fakes.dart' show adminNow;

InventoryRow row(
  String sku, {
  required String name,
  Map<String, String> attributes = const {},
  required int onHand,
  int reserved = 0,
  int alertAt = 10,
  bool stocked = true,
  LastChange? last,
}) => InventoryRow(
  variantId: 'v-$sku',
  productId: 'p-$name',
  sku: sku,
  name: I18nText(en: name),
  attributes: attributes,
  onHand: onHand,
  reserved: reserved,
  alertAt: alertAt,
  state: stocked
      ? InventoryState.of(available: onHand - reserved, alertAt: alertAt)
      : InventoryState.none,
  last: last,
);

/// A-06 as in the design: low lamp and headphones, a sold-out colour, a
/// healthy watch and a rice cooker that was never stocked.
final seedRows = [
  row(
    'LMP-LED-WHT',
    name: 'LED Desk Lamp',
    attributes: {'colour': 'White'},
    onHand: 4,
    reserved: 1,
    last: LastChange(
      reason: StockReason.sold,
      delta: -2,
      at: adminNow.subtract(const Duration(hours: 1)),
      orderNumber: 'K-10253',
    ),
  ),
  row(
    'HP-PRO-BLK',
    name: 'Wireless Headphones Pro',
    attributes: {'colour': 'Black'},
    onHand: 12,
    reserved: 1,
    alertAt: 15,
  ),
  row(
    'HP-PRO-SKY',
    name: 'Wireless Headphones Pro',
    attributes: {'colour': 'Sky'},
    onHand: 0,
  ),
  row(
    'SW-ACT2-BLK',
    name: 'Smart Watch Active 2',
    attributes: {'colour': 'Black'},
    onHand: 58,
    alertAt: 8,
    last: LastChange(
      reason: StockReason.adjustment,
      delta: -1,
      note: 'Count correction',
      at: adminNow.subtract(const Duration(days: 1)),
      actor: 'Visal Keo',
    ),
  ),
  row('RCK-18-WHT', name: 'Rice Cooker 1.8 L', onHand: 0, stocked: false),
];

final seedHistory = [
  StockMovement(
    at: adminNow.subtract(const Duration(hours: 2)),
    sku: 'LMP-LED-WHT',
    label: 'LED Desk Lamp · White',
    reason: StockReason.received,
    delta: 50,
    note: 'DN-2210',
    actor: 'Visal Keo',
  ),
  StockMovement(
    at: adminNow.subtract(const Duration(hours: 3)),
    sku: 'LMP-LED-WHT',
    label: 'LED Desk Lamp · White',
    reason: StockReason.reserved,
    delta: -1,
    orderNumber: 'K-10253',
  ),
];

/// In-memory inventory: filters and searches [rows] like the RPC does.
class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository({
    List<InventoryRow>? rows,
    List<StockMovement>? history,
  }) : rows = rows ?? seedRows,
       historyRows = history ?? seedHistory;

  final List<InventoryRow> rows;
  final List<StockMovement> historyRows;
  final queries = <InventoryQuery>[];
  final adjustments = <(StockAdjustment, String?)>[];

  /// A one-shot answer for the next adjust.
  InventoryOutcome? next;
  bool failList = false;

  bool _matches(InventoryRow r, String search) =>
      search.isEmpty ||
      r.sku.toLowerCase().contains(search.toLowerCase()) ||
      r.name.en.toLowerCase().contains(search.toLowerCase());

  @override
  Future<InventoryPage> list(InventoryQuery query) async {
    queries.add(query);
    if (failList) throw Exception('offline');
    final searched = rows.where((r) => _matches(r, query.search.trim()));
    bool restock(InventoryRow r) =>
        r.state == InventoryState.low || r.state == InventoryState.out;
    final filtered = searched.where(
      (r) => switch (query.filter) {
        InventoryFilter.restock => restock(r),
        InventoryFilter.out => r.state == InventoryState.out,
        InventoryFilter.all => true,
      },
    );
    return InventoryPage(
      rows: filtered.toList(),
      total: filtered.length,
      summary: InventorySummary(
        low: rows.where((r) => r.state == InventoryState.low).length,
        out: rows.where((r) => r.state == InventoryState.out).length,
        reservedUnits: rows.fold(0, (n, r) => n + r.reserved),
        stockValueCents: 4821000,
      ),
      counts: {
        InventoryFilter.restock: searched.where(restock).length,
        InventoryFilter.out: searched
            .where((r) => r.state == InventoryState.out)
            .length,
        InventoryFilter.all: searched.length,
      },
    );
  }

  @override
  Future<List<StockMovement>> history({
    String? variantId,
    int limit = 30,
  }) async => historyRows;

  @override
  Future<InventoryOutcome> adjust(
    StockAdjustment adjustment, {
    String? reasonLabel,
  }) async {
    adjustments.add((adjustment, reasonLabel));
    final answer = next;
    next = null;
    if (answer != null) return answer;
    final current = rows.firstWhere((r) => r.variantId == adjustment.variantId);
    final after = onHandAfter(adjustment.mode, current.onHand, adjustment.qty)!;
    return StockAdjusted(
      onHand: after,
      reserved: current.reserved,
      delta: after - current.onHand,
    );
  }
}

List<Override> inventoryOverrides(FakeInventoryRepository inventory) => [
  inventoryRepositoryProvider.overrideWithValue(inventory),
];

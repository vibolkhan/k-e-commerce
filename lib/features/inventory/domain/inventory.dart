import '../../catalog/domain/i18n_text.dart';

// A-06 Inventory and A-06a Adjust stock (F10, ADM-03, CAT-05).
// Available = on hand − reserved; the server decides every number.

/// A-06 filter chips. `restock` is low or out of stock.
enum InventoryFilter {
  restock,
  out,
  all;

  static InventoryFilter fromWire(Object? value) =>
      values.where((f) => f.name == value).firstOrNull ?? restock;
}

/// One variant's stock state: out (nothing available), low (available at or
/// under its alert level), ok, or none (never stocked).
enum InventoryState {
  out,
  low,
  ok,
  none;

  static InventoryState fromWire(Object? value) =>
      values.where((s) => s.name == value).firstOrNull ?? ok;

  /// The state a count would have: what the A-06a preview shows.
  static InventoryState of({required int available, required int alertAt}) =>
      available <= 0
      ? out
      : available <= alertAt
      ? low
      : ok;
}

/// The ledger reasons (`stock_reason`).
enum StockReason {
  received,
  adjustment,
  damaged,
  reserved,
  released,
  sold,
  returned;

  static StockReason fromWire(Object? value) =>
      values.where((r) => r.name == value).firstOrNull ?? adjustment;
}

class InventoryQuery {
  const InventoryQuery({
    this.filter = InventoryFilter.restock,
    this.search = '',
    this.page = 0,
  });

  static const pageSize = 25;

  final InventoryFilter filter;
  final String search;
  final int page;

  /// A new filter or search starts again at the first page.
  InventoryQuery copyWith({
    InventoryFilter? filter,
    String? search,
    int? page,
  }) => InventoryQuery(
    filter: filter ?? this.filter,
    search: search ?? this.search,
    page: page ?? (filter == null && search == null ? this.page : 0),
  );

  @override
  bool operator ==(Object other) =>
      other is InventoryQuery &&
      other.filter == filter &&
      other.search == search &&
      other.page == page;

  @override
  int get hashCode => Object.hash(filter, search, page);
}

/// The last stock change on a row ("2 sold", "Count correction −1").
class LastChange {
  const LastChange({
    required this.reason,
    required this.delta,
    this.note,
    this.at,
    this.actor,
    this.orderNumber,
  });

  factory LastChange.fromJson(Map<String, dynamic> json) => LastChange(
    reason: StockReason.fromWire(json['reason']),
    delta: (json['delta'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
    at: DateTime.tryParse(json['at'] as String? ?? ''),
    actor: json['actor'] as String?,
    orderNumber: json['order_number'] as String?,
  );

  final StockReason reason;
  final int delta;
  final String? note;
  final DateTime? at;
  final String? actor;
  final String? orderNumber;
}

class InventoryRow {
  const InventoryRow({
    required this.variantId,
    required this.productId,
    required this.sku,
    required this.name,
    this.attributes = const {},
    this.mainImageUrl,
    required this.onHand,
    required this.reserved,
    required this.alertAt,
    required this.state,
    this.last,
  });

  factory InventoryRow.fromRow(
    Map<String, dynamic> row, {
    String? Function(String? path)? imageUrl,
  }) => InventoryRow(
    variantId: row['variant_id'] as String,
    productId: row['product_id'] as String,
    sku: row['sku'] as String,
    name: I18nText.fromJson(row['name']),
    attributes: {
      for (final e in (row['attributes'] as Map? ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
    mainImageUrl: imageUrl?.call(row['main_image'] as String?),
    onHand: (row['on_hand'] as num?)?.toInt() ?? 0,
    reserved: (row['reserved'] as num?)?.toInt() ?? 0,
    alertAt: (row['alert_at'] as num?)?.toInt() ?? 0,
    state: InventoryState.fromWire(row['state']),
    last: row['last'] is Map
        ? LastChange.fromJson((row['last'] as Map).cast<String, dynamic>())
        : null,
  );

  final String variantId;
  final String productId;
  final String sku;
  final I18nText name;
  final Map<String, String> attributes;
  final String? mainImageUrl;
  final int onHand;
  final int reserved;
  final int alertAt;
  final InventoryState state;
  final LastChange? last;

  int get available => onHand - reserved;

  /// "White", "White / M": the attribute values in key order.
  String get variantLabel {
    final keys = attributes.keys.toList()..sort();
    return keys.map((k) => attributes[k]).join(' / ');
  }
}

class InventorySummary {
  const InventorySummary({
    this.low = 0,
    this.out = 0,
    this.reservedUnits = 0,
    this.stockValueCents = 0,
  });

  factory InventorySummary.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return InventorySummary(
      low: read('low'),
      out: read('out'),
      reservedUnits: read('reserved_units'),
      stockValueCents: read('stock_value_cents'),
    );
  }

  final int low;
  final int out;
  final int reservedUnits;
  final int stockValueCents;
}

class InventoryPage {
  const InventoryPage({
    this.rows = const [],
    this.total = 0,
    this.summary = const InventorySummary(),
    this.counts = const {},
  });

  final List<InventoryRow> rows;
  final int total;
  final InventorySummary summary;
  final Map<InventoryFilter, int> counts;

  static Map<InventoryFilter, int> countsFromJson(Object? json) => {
    if (json is Map)
      for (final f in InventoryFilter.values)
        if (json[f.name] is num) f: (json[f.name] as num).toInt(),
  };
}

/// One line of the stock ledger (A-06a history, "View adjustment history").
class StockMovement {
  const StockMovement({
    required this.at,
    required this.sku,
    required this.label,
    required this.reason,
    required this.delta,
    this.note,
    this.orderNumber,
    this.actor,
  });

  factory StockMovement.fromRow(Map<String, dynamic> row) => StockMovement(
    at: DateTime.parse(row['at'] as String),
    sku: row['sku'] as String? ?? '',
    label: row['label'] as String? ?? '',
    reason: StockReason.fromWire(row['reason']),
    delta: (row['delta'] as num?)?.toInt() ?? 0,
    note: row['note'] as String?,
    orderNumber: row['order_number'] as String?,
    actor: row['actor_name'] as String?,
  );

  final DateTime at;
  final String sku;
  final String label;
  final StockReason reason;
  final int delta;
  final String? note;
  final String? orderNumber;
  final String? actor;
}

// ---------------------------------------------------------------- A-06a

enum AdjustMode { add, remove, set }

/// The A-06a reason menu. Several labels share a ledger reason; the label
/// goes in front of the note so the history reads as staff chose it.
enum AdjustReason {
  receivedFromSupplier(StockReason.received, {AdjustMode.add}),
  returnedToStock(StockReason.returned, {AdjustMode.add}),
  damaged(StockReason.damaged, {AdjustMode.remove}),
  lost(StockReason.adjustment, {AdjustMode.remove}),
  usedInStore(StockReason.adjustment, {AdjustMode.remove}),
  countCorrection(StockReason.adjustment, {
    AdjustMode.add,
    AdjustMode.remove,
    AdjustMode.set,
  });

  const AdjustReason(this.wire, this.modes);

  final StockReason wire;
  final Set<AdjustMode> modes;

  static List<AdjustReason> forMode(AdjustMode mode) =>
      values.where((r) => r.modes.contains(mode)).toList();

  /// The reason a mode starts with.
  static AdjustReason defaultFor(AdjustMode mode) => switch (mode) {
    AdjustMode.add => receivedFromSupplier,
    AdjustMode.remove => damaged,
    AdjustMode.set => countCorrection,
  };

  /// Labels that the ledger reason alone can't tell apart.
  bool get labelsNote =>
      this == lost || this == usedInStore || this == countCorrection;
}

/// On hand after saving: what the A-06a preview strip shows. Null when the
/// quantity isn't a number yet.
int? onHandAfter(AdjustMode mode, int onHand, int? qty) => switch (qty) {
  null => null,
  final q => switch (mode) {
    AdjustMode.add => onHand + q,
    AdjustMode.remove => onHand - q,
    AdjustMode.set => q,
  },
};

/// Why the A-06a form can't be saved yet, or null when it can.
enum AdjustProblem { qtyRequired, qtyTooLarge, belowReserved, noChange }

AdjustProblem? adjustProblem({
  required AdjustMode mode,
  required int onHand,
  required int reserved,
  required int? qty,
}) {
  if (qty == null || (mode != AdjustMode.set && qty <= 0) || qty < 0) {
    return AdjustProblem.qtyRequired;
  }
  if (qty > maxAdjustQty) return AdjustProblem.qtyTooLarge;
  final after = onHandAfter(mode, onHand, qty)!;
  if (after < reserved) return AdjustProblem.belowReserved;
  if (after == onHand) return AdjustProblem.noChange;
  return null;
}

/// Matches the inventory-manage limit.
const maxAdjustQty = 100000;
const maxAdjustNote = 500;

class StockAdjustment {
  const StockAdjustment({
    required this.variantId,
    required this.mode,
    required this.qty,
    required this.reason,
    this.note = '',
  });

  final String variantId;
  final AdjustMode mode;
  final int qty;
  final AdjustReason reason;
  final String note;

  /// The inventory-manage body. [reasonLabel] is the English label of a
  /// reason the ledger can't tell apart, kept in front of the note.
  Map<String, dynamic> toPayload({String? reasonLabel}) {
    final trimmed = note.trim();
    final fullNote = [
      if (reason.labelsNote && reasonLabel != null) reasonLabel,
      if (trimmed.isNotEmpty) trimmed,
    ].join(' · ');
    return {
      'action': 'adjust',
      'variant_id': variantId,
      'mode': mode.name,
      'qty': qty,
      'reason': reason.wire.name,
      if (fullNote.isNotEmpty) 'note': fullNote,
    };
  }
}

/// What inventory-manage answered (HTTP 200 with a `status`).
sealed class InventoryOutcome {
  const InventoryOutcome();

  factory InventoryOutcome.fromJson(Map<String, dynamic> json) =>
      switch (json['status']) {
        'adjusted' => StockAdjusted(
          onHand: (json['on_hand'] as num?)?.toInt() ?? 0,
          reserved: (json['reserved'] as num?)?.toInt() ?? 0,
          delta: (json['delta'] as num?)?.toInt() ?? 0,
        ),
        'below_reserved' => StockBelowReserved(
          (json['reserved'] as num?)?.toInt() ?? 0,
        ),
        'invalid' => const InventoryRefused(InventoryRefusal.invalid),
        'not_found' => const InventoryRefused(InventoryRefusal.notFound),
        'forbidden' => const InventoryRefused(InventoryRefusal.forbidden),
        _ => const InventoryRefused(InventoryRefusal.unknown),
      };
}

class StockAdjusted extends InventoryOutcome {
  const StockAdjusted({
    required this.onHand,
    required this.reserved,
    required this.delta,
  });

  final int onHand;
  final int reserved;
  final int delta;
}

/// Open orders hold more than the new count would leave.
class StockBelowReserved extends InventoryOutcome {
  const StockBelowReserved(this.reserved);
  final int reserved;
}

enum InventoryRefusal { invalid, notFound, forbidden, unknown }

class InventoryRefused extends InventoryOutcome {
  const InventoryRefused(this.reason);
  final InventoryRefusal reason;
}

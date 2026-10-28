import 'i18n_text.dart';
import 'product_draft.dart';

/// A-05 status tabs. "All" leaves archived products out, like the design's
/// counts (All 248 = Active 231 + Draft 12 + 5 hidden elsewhere).
enum CatalogTab { all, active, draft, archived }

/// A-05 "Stock" filter.
enum StockFilter {
  any('any'),
  inStock('in'),
  low('low'),
  out('out');

  const StockFilter(this.wire);
  final String wire;
}

/// The A-05 stock pill.
enum StockState {
  inStock,
  low,
  out,

  /// No stock row yet: "Not stocked".
  none;

  static StockState fromWire(Object? value) => switch (value) {
    'in' => inStock,
    'low' => low,
    'out' => out,
    _ => none,
  };
}

class CatalogListQuery {
  const CatalogListQuery({
    this.tab = CatalogTab.all,
    this.search = '',
    this.categoryId,
    this.stock = StockFilter.any,
    this.quoteOnly = false,
    this.page = 0,
  });

  static const pageSize = 25;

  final CatalogTab tab;
  final String search;
  final String? categoryId;
  final StockFilter stock;
  final bool quoteOnly;
  final int page;

  /// A new filter starts at the first page.
  CatalogListQuery copyWith({
    CatalogTab? tab,
    String? search,
    String? Function()? categoryId,
    StockFilter? stock,
    bool? quoteOnly,
    int? page,
  }) => CatalogListQuery(
    tab: tab ?? this.tab,
    search: search ?? this.search,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    stock: stock ?? this.stock,
    quoteOnly: quoteOnly ?? this.quoteOnly,
    page: page ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is CatalogListQuery &&
      other.tab == tab &&
      other.search == search &&
      other.categoryId == categoryId &&
      other.stock == stock &&
      other.quoteOnly == quoteOnly &&
      other.page == page;

  @override
  int get hashCode =>
      Object.hash(tab, search, categoryId, stock, quoteOnly, page);
}

/// One A-05 row (`catalog_admin_list`).
class CatalogListItem {
  const CatalogListItem({
    required this.id,
    required this.name,
    required this.status,
    this.brand,
    this.categoryId,
    this.category = const I18nText(),
    this.firstSku,
    this.variantCount = 0,
    this.minPriceCents,
    this.maxPriceCents,
    this.available = 0,
    this.outCount = 0,
    this.stock = StockState.none,
    this.rfqEnabled = false,
    this.rfqMinQty,
    this.mainImageUrl,
    this.updatedAt,
    this.updatedBy,
  });

  factory CatalogListItem.fromRow(
    Map<String, dynamic> row, {
    String? Function(String? path)? imageUrl,
  }) => CatalogListItem(
    id: row['id'] as String,
    name: I18nText.fromJson(row['name']),
    status: ProductStatus.fromDb(row['status']),
    brand: row['brand'] as String?,
    categoryId: row['category_id'] as String?,
    category: I18nText.fromJson(row['category']),
    firstSku: row['first_sku'] as String?,
    variantCount: (row['variant_count'] as num?)?.toInt() ?? 0,
    minPriceCents: (row['min_price_cents'] as num?)?.toInt(),
    maxPriceCents: (row['max_price_cents'] as num?)?.toInt(),
    available: (row['available'] as num?)?.toInt() ?? 0,
    outCount: (row['out_count'] as num?)?.toInt() ?? 0,
    stock: StockState.fromWire(row['stock_state']),
    rfqEnabled: row['rfq_enabled'] == true,
    rfqMinQty: (row['rfq_min_qty'] as num?)?.toInt(),
    mainImageUrl: imageUrl?.call(row['main_image'] as String?),
    updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
    updatedBy: row['updated_by'] as String?,
  );

  final String id;
  final I18nText name;
  final ProductStatus status;
  final String? brand;
  final String? categoryId;
  final I18nText category;
  final String? firstSku;
  final int variantCount;
  final int? minPriceCents;
  final int? maxPriceCents;
  final int available;
  final int outCount;
  final StockState stock;
  final bool rfqEnabled;
  final int? rfqMinQty;
  final String? mainImageUrl;
  final DateTime? updatedAt;
  final String? updatedBy;
}

class CatalogPage {
  const CatalogPage({
    this.rows = const [],
    this.total = 0,
    this.counts = const {},
  });

  final List<CatalogListItem> rows;

  /// Rows in the selected tab (for pagination).
  final int total;
  final Map<CatalogTab, int> counts;

  static Map<CatalogTab, int> countsFromJson(Object? json) => {
    if (json is Map)
      for (final tab in CatalogTab.values)
        tab: (json[tab.name] as num?)?.toInt() ?? 0,
  };
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.parentId,
    this.slug = '',
  });

  factory Category.fromRow(Map<String, dynamic> row) => Category(
    id: row['id'] as String,
    name: I18nText.fromJson(row['name']),
    parentId: row['parent_id'] as String?,
    slug: row['slug'] as String? ?? '',
  );

  final String id;
  final I18nText name;
  final String? parentId;
  final String slug;
}

/// Categories in tree order with their "Electronics › Audio" paths.
List<({Category category, String path, int depth})> categoryTree(
  List<Category> all,
  String languageCode,
) {
  final out = <({Category category, String path, int depth})>[];
  void walk(String? parent, String prefix, int depth) {
    for (final c in all.where((c) => c.parentId == parent)) {
      final path = prefix.isEmpty
          ? c.name.of(languageCode)
          : '$prefix › ${c.name.of(languageCode)}';
      out.add((category: c, path: path, depth: depth));
      walk(c.id, path, depth + 1);
    }
  }

  walk(null, '', 0);
  return out;
}

/// A-05b price history (`product_price_history`).
class PriceChange {
  const PriceChange({
    required this.at,
    required this.sku,
    required this.isNew,
    this.oldCents,
    this.newCents,
    this.actorName,
  });

  factory PriceChange.fromRow(Map<String, dynamic> row) => PriceChange(
    at: DateTime.parse(row['at'] as String),
    sku: row['sku'] as String? ?? '',
    isNew: row['action'] == 'insert',
    oldCents: (row['old_cents'] as num?)?.toInt(),
    newCents: (row['new_cents'] as num?)?.toInt(),
    actorName: row['actor_name'] as String?,
  );

  final DateTime at;
  final String sku;

  /// The first price of a variant.
  final bool isNew;
  final int? oldCents;
  final int? newCents;
  final String? actorName;
}

/// A-05e: what archiving touches (`catalog_archive_impact`).
class ArchiveImpact {
  const ArchiveImpact({
    this.variants = 0,
    this.inStock = 0,
    this.openOrders = 0,
    this.openRfqs = 0,
  });

  factory ArchiveImpact.fromJson(Map<String, dynamic> json) => ArchiveImpact(
    variants: (json['variants'] as num?)?.toInt() ?? 0,
    inStock: (json['in_stock'] as num?)?.toInt() ?? 0,
    openOrders: (json['open_orders'] as num?)?.toInt() ?? 0,
    openRfqs: (json['open_rfqs'] as num?)?.toInt() ?? 0,
  );

  final int variants;
  final int inStock;
  final int openOrders;
  final int openRfqs;
}

import '../../catalog/domain/i18n_text.dart';

/// Who is browsing, for audience-targeted banners and collections. Guests
/// and customers are [retail].
enum Audience {
  retail,
  business;

  /// The `audience` values (`all`, `retail`, `business`) this viewer sees.
  List<String> get visible => ['all', name];
}

/// C-03b sort options. [curated] keeps a collection's own order (home rails)
/// and [relevance] is "Best match" for search results (C-04a); neither is
/// offered outside its own list.
enum BrowseSort {
  relevance('relevance'),
  popular('popular'),
  newest('newest'),
  priceAsc('price_asc'),
  priceDesc('price_desc'),
  rating('rating'),
  curated('curated');

  const BrowseSort(this.wire);

  final String wire;

  bool get isPrice => this == priceAsc || this == priceDesc;

  /// The options in the sort sheet, with Best match first for search
  /// results. Business buyers never see prices, so they can't sort by them
  /// either (App Flow F3).
  static List<BrowseSort> options({
    required bool business,
    bool search = false,
  }) => [
    if (search) relevance,
    popular,
    newest,
    if (!business) ...[priceAsc, priceDesc],
    rating,
  ];
}

/// What the product list (C-03) and search results (C-04a) show: one
/// category or collection and/or a search, the filters from the chips and
/// the C-03a sheet, the sort, and the page.
class BrowseQuery {
  const BrowseQuery({
    this.categoryId,
    this.collection,
    this.search,
    this.brands = const {},
    this.minCents,
    this.maxCents,
    this.minRating,
    this.inStock = false,
    this.sameDay = false,
    this.sort = BrowseSort.popular,
    this.page = 0,
    this.pageSize = defaultPageSize,
  });

  static const defaultPageSize = 20;

  /// The "Under $50" chip.
  static const underChipCents = 5000;

  final String? categoryId;

  /// Collection slug, e.g. `best-sellers`.
  final String? collection;

  /// What the shopper searched for (C-04), as typed.
  final String? search;
  final Set<String> brands;
  final int? minCents;
  final int? maxCents;
  final double? minRating;
  final bool inStock;
  final bool sameDay;
  final BrowseSort sort;
  final int page;
  final int pageSize;

  int get offset => page * pageSize;

  /// The number on the Filters chip: one per kind of filter in use.
  int get activeFilterCount =>
      (brands.isNotEmpty ? 1 : 0) +
      (minCents != null || maxCents != null ? 1 : 0) +
      (minRating != null ? 1 : 0) +
      (inStock ? 1 : 0) +
      (sameDay ? 1 : 0);

  bool get isUnderChipOn => minCents == null && maxCents == underChipCents;

  /// Any change goes back to the first page.
  BrowseQuery copyWith({
    Set<String>? brands,
    int? Function()? minCents,
    int? Function()? maxCents,
    double? Function()? minRating,
    bool? inStock,
    bool? sameDay,
    BrowseSort? sort,
  }) => BrowseQuery(
    categoryId: categoryId,
    collection: collection,
    search: search,
    brands: brands ?? this.brands,
    minCents: minCents == null ? this.minCents : minCents(),
    maxCents: maxCents == null ? this.maxCents : maxCents(),
    minRating: minRating == null ? this.minRating : minRating(),
    inStock: inStock ?? this.inStock,
    sameDay: sameDay ?? this.sameDay,
    sort: sort ?? this.sort,
    pageSize: pageSize,
  );

  BrowseQuery atPage(int page) => BrowseQuery(
    categoryId: categoryId,
    collection: collection,
    search: search,
    brands: brands,
    minCents: minCents,
    maxCents: maxCents,
    minRating: minRating,
    inStock: inStock,
    sameDay: sameDay,
    sort: sort,
    page: page,
    pageSize: pageSize,
  );

  /// Same category or collection, no filters, the sort kept.
  BrowseQuery cleared() => BrowseQuery(
    categoryId: categoryId,
    collection: collection,
    search: search,
    sort: sort,
    pageSize: pageSize,
  );

  /// What a business buyer may ask for: price filters and sorts dropped.
  BrowseQuery forBusiness() => BrowseQuery(
    categoryId: categoryId,
    collection: collection,
    search: search,
    brands: brands,
    minRating: minRating,
    inStock: inStock,
    sameDay: sameDay,
    sort: sort.isPrice ? BrowseSort.popular : sort,
    page: page,
    pageSize: pageSize,
  );

  /// `catalog_browse` arguments.
  Map<String, Object?> toRpcParams() => {
    'p_category': categoryId,
    'p_collection': collection,
    'p_brands': brands.isEmpty ? null : (brands.toList()..sort()),
    'p_min_cents': minCents,
    'p_max_cents': maxCents,
    'p_min_rating': minRating,
    'p_in_stock': inStock,
    'p_same_day': sameDay,
    'p_sort': sort.wire,
    'p_limit': pageSize,
    'p_offset': offset,
    'p_q': search,
  };

  @override
  bool operator ==(Object other) =>
      other is BrowseQuery &&
      other.categoryId == categoryId &&
      other.collection == collection &&
      other.search == search &&
      _sameSet(other.brands, brands) &&
      other.minCents == minCents &&
      other.maxCents == maxCents &&
      other.minRating == minRating &&
      other.inStock == inStock &&
      other.sameDay == sameDay &&
      other.sort == sort &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(
    categoryId,
    collection,
    search,
    Object.hashAllUnordered(brands),
    minCents,
    maxCents,
    minRating,
    inStock,
    sameDay,
    sort,
    page,
    pageSize,
  );

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

/// One product card in a list or rail.
class BrowseItem {
  const BrowseItem({
    required this.id,
    required this.slug,
    required this.name,
    this.brand,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.sameDay = true,
    this.tags = const [],
    this.rfqEnabled = false,
    this.rfqMinQty,
    this.priceCents,
    this.compareAtCents,
    this.available = 0,
    this.imageUrl,
  });

  factory BrowseItem.fromRow(
    Map<String, dynamic> row, {
    required String Function(String path) imageUrl,
  }) {
    final image = row['main_image'] as String?;
    return BrowseItem(
      id: row['id'] as String,
      slug: row['slug'] as String? ?? '',
      name: I18nText.fromJson(row['name']),
      brand: row['brand'] as String?,
      ratingAvg: (row['rating_avg'] as num?)?.toDouble() ?? 0,
      ratingCount: (row['rating_count'] as num?)?.toInt() ?? 0,
      sameDay: row['same_day'] != false,
      tags: [for (final t in row['tags'] as List? ?? const []) t.toString()],
      rfqEnabled: row['rfq_enabled'] == true,
      rfqMinQty: (row['rfq_min_qty'] as num?)?.toInt(),
      priceCents: (row['min_price_cents'] as num?)?.toInt(),
      compareAtCents: (row['compare_at_cents'] as num?)?.toInt(),
      available: (row['available'] as num?)?.toInt() ?? 0,
      imageUrl: image == null || image.isEmpty ? null : imageUrl(image),
    );
  }

  final String id;
  final String slug;
  final I18nText name;
  final String? brand;
  final double ratingAvg;
  final int ratingCount;
  final bool sameDay;
  final List<String> tags;
  final bool rfqEnabled;
  final int? rfqMinQty;

  /// The lowest variant price ("from"); null for business buyers.
  final int? priceCents;
  final int? compareAtCents;
  final int available;
  final String? imageUrl;

  bool get soldOut => available <= 0;
}

class BrandFacet {
  const BrandFacet(this.brand, this.count);
  final String brand;
  final int count;
}

/// One page of `catalog_browse`, with the facets for the filter sheet.
class BrowsePage {
  const BrowsePage({
    this.items = const [],
    this.total = 0,
    this.brands = const [],
    this.minPriceCents,
    this.maxPriceCents,
    this.allSameDay = false,
  });

  factory BrowsePage.fromJson(
    Map<String, dynamic> json, {
    required String Function(String path) imageUrl,
  }) {
    final bounds = json['price_bounds'];
    return BrowsePage(
      items: [
        for (final r in json['rows'] as List? ?? const [])
          BrowseItem.fromRow(r as Map<String, dynamic>, imageUrl: imageUrl),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      brands: [
        for (final b in json['brands'] as List? ?? const [])
          BrandFacet(
            (b as Map)['brand'] as String,
            (b['count'] as num).toInt(),
          ),
      ],
      minPriceCents: bounds is Map ? (bounds['min'] as num?)?.toInt() : null,
      maxPriceCents: bounds is Map ? (bounds['max'] as num?)?.toInt() : null,
      allSameDay: json['all_same_day'] == true,
    );
  }

  static const empty = BrowsePage();

  final List<BrowseItem> items;
  final int total;
  final List<BrandFacet> brands;
  final int? minPriceCents;
  final int? maxPriceCents;
  final bool allSameDay;
}

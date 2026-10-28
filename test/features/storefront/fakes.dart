import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:k_e_commerce/core/money/khr_rate_provider.dart';
import 'package:k_e_commerce/core/time/cutoff.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/storefront/data/storefront_repository.dart';
import 'package:k_e_commerce/features/storefront/domain/browse.dart';
import 'package:k_e_commerce/features/storefront/domain/storefront.dart';

/// 2026-10-27 10:25 in Phnom Penh: 4h 35m before the 3 PM cut-off.
final storeNow = DateTime.utc(2026, 10, 27, 3, 25);

const electronics = StoreCategory(
  id: 'c-elec',
  slug: 'electronics',
  name: I18nText(en: 'Electronics', km: 'គ្រឿងអេឡិចត្រូនិក'),
  icon: 'devices',
  sort: 1,
);
const audioCat = StoreCategory(
  id: 'c-audio',
  slug: 'audio',
  name: I18nText(en: 'Audio', km: 'សំឡេង'),
  parentId: 'c-elec',
  icon: 'headphones',
  sort: 2,
);
const kitchenCat = StoreCategory(
  id: 'c-kitchen',
  slug: 'kitchen',
  name: I18nText(en: 'Kitchen', km: 'ផ្ទះបាយ'),
  icon: 'kitchen',
  sort: 3,
);
const pantryCat = StoreCategory(
  id: 'c-pantry',
  slug: 'pantry',
  name: I18nText(en: 'Pantry'),
  icon: 'pantry',
  sort: 4,
);
const storeCategories = [electronics, audioCat, kitchenCat, pantryCat];

/// A fake product: [cents] null makes it look like a business buyer's row.
class FakeProduct {
  const FakeProduct({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.cents,
    this.brand = 'Sonora',
    this.rating = 4.5,
    this.ratingCount = 10,
    this.sold = 0,
    this.available = 10,
    this.sameDay = true,
    this.rfqMinQty,
    this.created = 0,
  });

  final String id;
  final String name;
  final String categoryId;
  final int cents;
  final String brand;
  final double rating;
  final int ratingCount;
  final int sold;
  final int available;
  final bool sameDay;
  final int? rfqMinQty;

  /// Higher is newer.
  final int created;

  BrowseItem item({required bool business}) => BrowseItem(
    id: id,
    slug: id,
    name: I18nText(en: name),
    brand: brand,
    ratingAvg: rating,
    ratingCount: ratingCount,
    sameDay: sameDay,
    rfqMinQty: rfqMinQty,
    priceCents: business ? null : cents,
    available: available,
  );
}

const headphonesPro = FakeProduct(
  id: 'p-hp',
  name: 'Wireless Headphones Pro',
  categoryId: 'c-audio',
  cents: 4900,
  rating: 4.6,
  ratingCount: 128,
  sold: 840,
  rfqMinQty: 5,
);
const speakerMini = FakeProduct(
  id: 'p-spk',
  name: 'Bluetooth Speaker Mini',
  categoryId: 'c-audio',
  cents: 2900,
  brand: 'Nimbus',
  sold: 260,
  available: 0,
  created: 2,
);
const mugSet = FakeProduct(
  id: 'p-mug',
  name: 'Ceramic Coffee Mug Set',
  categoryId: 'c-kitchen',
  cents: 1800,
  brand: 'K Basics',
  rating: 4.8,
  sold: 610,
  sameDay: false,
  created: 1,
);

/// In-memory storefront with the same filtering, sorting and paging rules
/// as `catalog_browse`. Records every browse query.
class FakeStorefrontRepository implements StorefrontRepository {
  FakeStorefrontRepository({
    this.categoryList = storeCategories,
    List<FakeProduct>? products,
    this.bannerList = const [],
    Map<String, List<String>>? collections,
    this.business = false,
    this.addressList = const [],
    this.failBrowse = false,
    DateTime? serverNow,
  }) : products = products ?? const [headphonesPro, speakerMini, mugSet],
       collections =
           collections ??
           const {
             'best-sellers': ['p-hp', 'p-mug'],
             'new-arrivals': ['p-spk'],
             'popular-for-offices': ['p-hp'],
           },
       serverNow = serverNow ?? storeNow;

  final List<StoreCategory> categoryList;
  final List<FakeProduct> products;
  final List<HomeBanner> bannerList;
  final Map<String, List<String>> collections;

  /// Behave like RLS for a business buyer: no prices.
  final bool business;
  final List<DeliverTo> addressList;

  /// Fail product-list reads (categories and collections pages, not the
  /// home rails).
  bool failBrowse;
  final DateTime serverNow;

  final queries = <BrowseQuery>[];
  final bannerAudiences = <Audience>[];

  @override
  Future<List<StoreCategory>> categories() async => categoryList;

  @override
  Future<List<HomeBanner>> banners(Audience audience) async {
    bannerAudiences.add(audience);
    return bannerList;
  }

  @override
  Future<I18nText?> collectionTitle(String slug) async => switch (slug) {
    'best-sellers' => const I18nText(en: 'Best sellers'),
    'new-arrivals' => const I18nText(en: 'New arrivals'),
    _ => null,
  };

  @override
  Future<StoreClock> clock(DateTime deviceNow) async => StoreClock(
    serverNow: serverNow,
    cutoff: Cutoff.standard,
    holidays: const {'2026-11-09'},
    fetchedAt: deviceNow,
  );

  @override
  Future<List<DeliverTo>> addresses() async => addressList;

  @override
  Future<BrowsePage> browse(BrowseQuery query) async {
    queries.add(query);
    if (failBrowse && query.sort != BrowseSort.curated) {
      throw Exception('offline');
    }
    Set<String> tree(String id) => {
      id,
      for (final c in categoryList)
        if (c.parentId == id) ...tree(c.id),
    };
    final inCategory = query.categoryId == null
        ? null
        : tree(query.categoryId!);
    final collection = query.collection == null
        ? null
        : collections[query.collection] ?? const [];
    final scoped = products.where(
      (p) =>
          (inCategory == null || inCategory.contains(p.categoryId)) &&
          (collection == null || collection.contains(p.id)) &&
          (!query.inStock || p.available > 0) &&
          (!query.sameDay || p.sameDay) &&
          (query.minRating == null || p.rating >= query.minRating!),
    );
    final priced = scoped.where(
      (p) =>
          business ||
          ((query.minCents == null || p.cents >= query.minCents!) &&
              (query.maxCents == null || p.cents <= query.maxCents!)),
    );
    final filtered = priced
        .where((p) => query.brands.isEmpty || query.brands.contains(p.brand))
        .toList();
    switch (query.sort) {
      case BrowseSort.curated when collection != null:
        filtered.sort(
          (a, b) =>
              collection.indexOf(a.id).compareTo(collection.indexOf(b.id)),
        );
      case BrowseSort.newest:
        filtered.sort((a, b) => b.created.compareTo(a.created));
      case BrowseSort.priceAsc when !business:
        filtered.sort((a, b) => a.cents.compareTo(b.cents));
      case BrowseSort.priceDesc when !business:
        filtered.sort((a, b) => b.cents.compareTo(a.cents));
      case BrowseSort.rating:
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
      default:
        filtered.sort((a, b) => b.sold.compareTo(a.sold));
    }
    final brandCounts = <String, int>{};
    for (final p in priced) {
      brandCounts[p.brand] = (brandCounts[p.brand] ?? 0) + 1;
    }
    final prices = [for (final p in scoped) p.cents];
    return BrowsePage(
      items: [
        for (final p in filtered.skip(query.offset).take(query.pageSize))
          p.item(business: business),
      ],
      total: filtered.length,
      brands: [for (final e in brandCounts.entries) BrandFacet(e.key, e.value)],
      minPriceCents: business || prices.isEmpty
          ? null
          : prices.reduce((a, b) => a < b ? a : b),
      maxPriceCents: business || prices.isEmpty
          ? null
          : prices.reduce((a, b) => a > b ? a : b),
      allSameDay: filtered.isNotEmpty && filtered.every((p) => p.sameDay),
    );
  }
}

/// Overrides for a storefront test: [repo], a fixed KHR rate and no
/// network clock surprises.
List<Override> storefrontOverrides(FakeStorefrontRepository repo) => [
  storefrontRepositoryProvider.overrideWithValue(repo),
  khrRateProvider.overrideWith((ref) async => 4100),
];

/// Many audio products, for paging.
List<FakeProduct> manyProducts(int n) => [
  for (var i = 0; i < n; i++)
    FakeProduct(
      id: 'p-$i',
      name: 'Speaker $i',
      categoryId: 'c-audio',
      cents: 1000 + i * 100,
      sold: 1000 - i,
    ),
];

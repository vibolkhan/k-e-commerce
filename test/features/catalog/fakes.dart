import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:k_e_commerce/core/money/khr_rate_provider.dart';
import 'package:k_e_commerce/features/catalog/data/catalog_repository.dart';
import 'package:k_e_commerce/features/catalog/data/file_pick.dart';
import 'package:k_e_commerce/features/catalog/data/product_read_repository.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_list.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_outcome.dart';
import 'package:k_e_commerce/features/catalog/domain/csv_import.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/catalog/domain/product_draft.dart';
import 'package:k_e_commerce/features/catalog/domain/product_view.dart';

import '../admin/fakes.dart' show adminNow;

const audio = Category(
  id: 'c-audio',
  name: I18nText(en: 'Audio', km: 'សំឡេង'),
  parentId: 'c-elec',
  slug: 'audio',
);
const kitchen = Category(
  id: 'c-kitchen',
  name: I18nText(en: 'Kitchen', km: 'ផ្ទះបាយ'),
  slug: 'kitchen',
);
const seedCategories = [
  Category(
    id: 'c-elec',
    name: I18nText(en: 'Electronics', km: 'គ្រឿងអេឡិចត្រូនិក'),
    slug: 'electronics',
  ),
  audio,
  kitchen,
];

/// A-05a/A-05b: Wireless Headphones Pro with three colours.
final headphones = ProductDraft(
  id: 'p-hp',
  categoryId: 'c-audio',
  slug: 'wireless-headphones-pro',
  brand: 'Sonora',
  name: const I18nText(en: 'Wireless Headphones Pro'),
  description: const I18nText(en: 'Over-ear headphones.'),
  tags: const ['Wireless'],
  options: const [
    ProductOption(
      name: I18nText(en: 'Colour'),
      values: ['Black', 'White', 'Sky'],
    ),
  ],
  status: ProductStatus.active,
  rfqEnabled: true,
  rfqMinQty: 5,
  variants: const [
    VariantDraft(
      id: 'v-blk',
      sku: 'HP-PRO-BLK',
      attributes: {'Colour': 'Black'},
      priceCents: 4900,
      onHand: 12,
      reserved: 1,
      lowStockAt: 15,
      stocked: true,
    ),
    VariantDraft(
      id: 'v-wht',
      sku: 'HP-PRO-WHT',
      attributes: {'Colour': 'White'},
      priceCents: 4900,
      onHand: 40,
      lowStockAt: 15,
      stocked: true,
    ),
    VariantDraft(
      id: 'v-sky',
      sku: 'HP-PRO-SKY',
      attributes: {'Colour': 'Sky'},
      priceCents: 4900,
      lowStockAt: 10,
      stocked: true,
    ),
  ],
  images: const [
    ImageDraft(
      id: 'i-1',
      path: 'products/p-hp/front.jpg',
      url: 'products/p-hp/front.jpg',
      alt: I18nText(en: 'Black headphones, front'),
      variantSku: 'HP-PRO-BLK',
    ),
  ],
  summary: ProductSummary(
    createdAt: DateTime.utc(2026, 9, 2, 3),
    createdBy: 'Visal Keo',
    updatedAt: adminNow,
    updatedBy: 'Chenda Lim',
    soldCount: 840,
    ratingAvg: 4.6,
    ratingCount: 128,
  ),
);

CatalogListItem listItem(
  String id,
  String name, {
  ProductStatus status = ProductStatus.active,
  StockState stock = StockState.inStock,
  int available = 52,
  int outCount = 0,
  bool rfq = false,
  int? minQty,
  int price = 4900,
}) => CatalogListItem(
  id: id,
  name: I18nText(en: name),
  status: status,
  brand: 'Sonora',
  categoryId: 'c-audio',
  category: const I18nText(en: 'Audio'),
  firstSku: '${id.toUpperCase()}-1',
  variantCount: 1,
  minPriceCents: price,
  maxPriceCents: price,
  available: available,
  outCount: outCount,
  stock: stock,
  rfqEnabled: rfq,
  rfqMinQty: minQty,
  updatedAt: adminNow,
  updatedBy: 'Visal Keo',
);

final seedList = [
  listItem(
    'p-hp',
    'Wireless Headphones Pro',
    stock: StockState.low,
    available: 52,
    outCount: 1,
    rfq: true,
    minQty: 5,
  ),
  listItem(
    'p-mug',
    'Ceramic Coffee Mug Set',
    rfq: true,
    minQty: 10,
    price: 1800,
  ),
  listItem(
    'p-spk',
    'Bluetooth Speaker Mini',
    stock: StockState.out,
    available: 0,
    price: 2900,
  ),
  listItem(
    'p-rice',
    'Rice Cooker 1.8 L',
    status: ProductStatus.draft,
    stock: StockState.none,
    available: 0,
    price: 4500,
  ),
  listItem('p-old', 'Old Speaker', status: ProductStatus.archived),
];

/// In-memory catalogue: filters [rows] like `catalog_admin_list`, records
/// every write in [calls], and answers writes with [next] once if set.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<CatalogListItem>? rows,
    Map<String, ProductDraft>? products,
  }) : rows = rows ?? [...seedList],
       products = products ?? {'p-hp': headphones};

  List<CatalogListItem> rows;
  Map<String, ProductDraft> products;
  final calls = <String>[];
  final saved = <ProductDraft>[];
  final queries = <CatalogListQuery>[];
  CatalogOutcome? next;
  ImportOutcome? nextImport;
  ArchiveImpact impact = const ArchiveImpact(
    variants: 3,
    inStock: 52,
    openOrders: 2,
    openRfqs: 1,
  );
  List<PriceChange> history = [
    PriceChange(
      at: adminNow,
      sku: 'HP-PRO-BLK',
      isNew: false,
      oldCents: 5200,
      newCents: 4900,
      actorName: 'Chenda Lim',
    ),
  ];

  CatalogOutcome _answer(String call, CatalogOutcome done) {
    calls.add(call);
    final scripted = next;
    next = null;
    return scripted ?? done;
  }

  @override
  Future<CatalogPage> list(CatalogListQuery query) async {
    queries.add(query);
    bool inTab(CatalogListItem r) => switch (query.tab) {
      CatalogTab.all => r.status != ProductStatus.archived,
      CatalogTab.active => r.status == ProductStatus.active,
      CatalogTab.draft => r.status == ProductStatus.draft,
      CatalogTab.archived => r.status == ProductStatus.archived,
    };
    final search = query.search.toLowerCase();
    final filtered = [
      for (final r in rows)
        if ((search.isEmpty ||
                r.name.en.toLowerCase().contains(search) ||
                (r.firstSku ?? '').toLowerCase().contains(search)) &&
            (query.categoryId == null || r.categoryId == query.categoryId) &&
            (!query.quoteOnly || r.rfqEnabled) &&
            switch (query.stock) {
              StockFilter.any => true,
              StockFilter.inStock => r.stock == StockState.inStock,
              StockFilter.low => r.stock == StockState.low,
              StockFilter.out =>
                r.stock == StockState.out || r.stock == StockState.none,
            })
          r,
    ];
    final tabRows = filtered.where(inTab).toList();
    final start = query.page * CatalogListQuery.pageSize;
    return CatalogPage(
      rows: tabRows.skip(start).take(CatalogListQuery.pageSize).toList(),
      total: tabRows.length,
      counts: {
        CatalogTab.all: filtered
            .where((r) => r.status != ProductStatus.archived)
            .length,
        CatalogTab.active: filtered
            .where((r) => r.status == ProductStatus.active)
            .length,
        CatalogTab.draft: filtered
            .where((r) => r.status == ProductStatus.draft)
            .length,
        CatalogTab.archived: filtered
            .where((r) => r.status == ProductStatus.archived)
            .length,
      },
    );
  }

  @override
  Future<List<Category>> categories() async => seedCategories;

  @override
  Future<ProductDraft?> product(String id) async => products[id];

  @override
  Future<List<PriceChange>> priceHistory(String productId) async => history;

  @override
  Future<ArchiveImpact> archiveImpact(String productId) async => impact;

  @override
  Future<CatalogOutcome> save(ProductDraft draft) async {
    saved.add(draft);
    final outcome = _answer(
      'save ${draft.id ?? 'new'}',
      CatalogSaved(draft.id ?? 'p-new'),
    );
    if (outcome is CatalogSaved && draft.isNew) {
      products[outcome.id] = ProductDraft(
        id: outcome.id,
        categoryId: draft.categoryId,
        name: draft.name,
        variants: draft.variants,
        images: draft.images,
      );
    }
    return outcome;
  }

  @override
  Future<CatalogOutcome> archive(String id) async =>
      _answer('archive $id', const CatalogUpdated(1));

  @override
  Future<CatalogOutcome> restore(String id) async =>
      _answer('restore $id', const CatalogUpdated(1));

  @override
  Future<CatalogOutcome> archiveMany(List<String> ids) async =>
      _answer('archive ${ids.join(',')}', CatalogUpdated(ids.length));

  @override
  Future<CatalogOutcome> moveMany(List<String> ids, String categoryId) async =>
      _answer('move ${ids.join(',')} $categoryId', CatalogUpdated(ids.length));

  var _uploads = 0;

  @override
  Future<ImageDraft?> uploadImage({
    required String folder,
    required String fileName,
    required Uint8List bytes,
  }) async {
    calls.add('upload $folder $fileName');
    final path = 'products/$folder/${_uploads++}.jpg';
    return ImageDraft(path: path, url: path);
  }

  final imports = <(String, String, Map<String, ImportField>)>[];

  @override
  Future<ImportOutcome> previewImport(
    String csv,
    Map<String, ImportField> mapping,
  ) async {
    imports.add(('preview', csv, mapping));
    final scripted = nextImport;
    nextImport = null;
    return scripted ??
        const ImportPreview(
          rows: 4,
          valid: 3,
          products: 2,
          errors: [ImportRowError(5, ImportErrorCode.skuExists, 'MUG-4-SND')],
        );
  }

  @override
  Future<ImportOutcome> commitImport(
    String csv,
    Map<String, ImportField> mapping,
  ) async {
    imports.add(('commit', csv, mapping));
    return const ImportDone(products: 2, variants: 3, skipped: 1, errors: []);
  }
}

class FakeProductReadRepository implements ProductReadRepository {
  FakeProductReadRepository([Map<String, ProductView>? products])
    : products = products ?? {'p-hp': headphonesView};

  final Map<String, ProductView> products;

  @override
  Future<ProductView?> product(String id) async => products[id];
}

const headphonesView = ProductView(
  id: 'p-hp',
  slug: 'wireless-headphones-pro',
  name: I18nText(en: 'Wireless Headphones Pro'),
  variants: [
    VariantView(
      id: 'v-blk',
      sku: 'HP-PRO-BLK',
      priceCents: 4900,
      available: 11,
    ),
  ],
  rfqEnabled: true,
  rfqMinQty: 5,
);

/// Files the next "choose file" returns.
class FakeFilePicker {
  List<PickedFile> next = [];
  final asked = <List<String>>[];

  Future<List<PickedFile>> pick({
    required List<String> extensions,
    bool multiple = false,
  }) async {
    asked.add(extensions);
    final files = next;
    next = [];
    return files;
  }
}

/// Overrides for [pumpAdmin] with the catalogue faked.
List<Override> catalogOverrides(
  FakeCatalogRepository catalog, {
  FakeProductReadRepository? read,
  FakeFilePicker? picker,
}) => [
  catalogRepositoryProvider.overrideWithValue(catalog),
  productReadRepositoryProvider.overrideWithValue(
    read ?? FakeProductReadRepository(),
  ),
  pickFilesProvider.overrideWithValue((picker ?? FakeFilePicker()).pick),
  khrRateProvider.overrideWith((ref) async => 4100),
];

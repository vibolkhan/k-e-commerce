import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/utils/log.dart';
import '../domain/catalog_list.dart';
import '../domain/catalog_outcome.dart';
import '../domain/csv_import.dart';
import '../domain/i18n_text.dart';
import '../domain/product_draft.dart';

/// Back-office catalogue (F09). Reads run under the caller's RLS; every
/// change goes through the catalog-manage / catalog-import Edge Functions,
/// which write as the staff member so price changes land in audit_logs.
/// Images upload straight to the product-images bucket (catalog staff only)
/// and are attached to the product when it is saved.
abstract interface class CatalogRepository {
  Future<CatalogPage> list(CatalogListQuery query);
  Future<List<Category>> categories();
  Future<ProductDraft?> product(String id);
  Future<List<PriceChange>> priceHistory(String productId);
  Future<ArchiveImpact> archiveImpact(String productId);

  Future<CatalogOutcome> save(ProductDraft draft);
  Future<CatalogOutcome> archive(String id);
  Future<CatalogOutcome> restore(String id);
  Future<CatalogOutcome> archiveMany(List<String> ids);
  Future<CatalogOutcome> moveMany(List<String> ids, String categoryId);

  /// Stores a picked photo and returns it as an unsaved [ImageDraft], or
  /// null when the upload failed.
  Future<ImageDraft?> uploadImage({
    required String folder,
    required String fileName,
    required Uint8List bytes,
  });

  Future<ImportOutcome> previewImport(
    String csv,
    Map<String, ImportField> mapping,
  );
  Future<ImportOutcome> commitImport(
    String csv,
    Map<String, ImportField> mapping,
  );
}

/// The storage path for a new photo: `products/<folder>/<random>.<ext>`.
String productImagePath(String folder, String fileName, Random random) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? 'jpg' : fileName.substring(dot + 1).toLowerCase();
  final id = List.generate(16, (_) => random.nextInt(16).toRadixString(16));
  return 'products/$folder/${id.join()}.${ext == 'jpeg' ? 'jpg' : ext}';
}

String? imageContentType(String fileName) =>
    switch (fileName.split('.').last.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };

/// A product row with its variants, prices, stock and images
/// (`CatalogRepository.product`).
const productDraftSelect =
    'id, category_id, slug, brand, name, description, highlights, specs, tags, '
    'options, status, is_best_seller, same_day, rfq_enabled, rfq_min_qty, '
    'rfq_multiple, sold_count, rating_avg, rating_count, created_at, updated_at, '
    'creator:profiles!products_created_by_fkey (full_name), '
    'editor:profiles!products_updated_by_fkey (full_name), '
    'product_variants (id, sku, barcode, attributes, active, sort, '
    'prices (amount_cents, compare_at_cents), '
    'stock (qty, reserved, low_stock_at)), '
    'product_images (id, path, alt, sort, variant_id)';

ProductDraft productDraftFromRow(
  Map<String, dynamic> row, {
  required String Function(String path) imageUrl,
}) {
  int bySort(dynamic a, dynamic b) =>
      ((a as Map)['sort'] as num).compareTo((b as Map)['sort'] as num);
  final variantRows = [...(row['product_variants'] as List? ?? const [])]
    ..sort(bySort);
  final skuById = {
    for (final v in variantRows) (v as Map)['id'] as String: v['sku'] as String,
  };
  final imageRows = [...(row['product_images'] as List? ?? const [])]
    ..sort(bySort);

  return ProductDraft(
    id: row['id'] as String,
    categoryId: row['category_id'] as String?,
    slug: row['slug'] as String? ?? '',
    brand: row['brand'] as String? ?? '',
    name: I18nText.fromJson(row['name']),
    description: I18nText.fromJson(row['description']),
    highlights: [
      for (final h in (row['highlights'] as List? ?? const []))
        I18nText.fromJson(h),
    ],
    specs: specsFromJson(row['specs']),
    tags: [for (final t in (row['tags'] as List? ?? const [])) t.toString()],
    options: [
      for (final o in (row['options'] as List? ?? const []))
        ProductOption.fromJson(o as Map<String, dynamic>),
    ],
    status: ProductStatus.fromDb(row['status']),
    isBestSeller: row['is_best_seller'] == true,
    sameDay: row['same_day'] != false,
    rfqEnabled: row['rfq_enabled'] == true,
    rfqMinQty: (row['rfq_min_qty'] as num?)?.toInt(),
    rfqMultiple: (row['rfq_multiple'] as num?)?.toInt() ?? 1,
    variants: [
      for (final v in variantRows.cast<Map<String, dynamic>>())
        _variantFromRow(v),
    ],
    images: [
      for (final i in imageRows.cast<Map<String, dynamic>>())
        ImageDraft(
          id: i['id'] as String,
          path: i['path'] as String,
          url: imageUrl(i['path'] as String),
          alt: I18nText.fromJson(i['alt']),
          variantSku: skuById[i['variant_id']],
        ),
    ],
    summary: ProductSummary(
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
      createdBy: (row['creator'] as Map?)?['full_name'] as String?,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? ''),
      updatedBy: (row['editor'] as Map?)?['full_name'] as String?,
      soldCount: (row['sold_count'] as num?)?.toInt() ?? 0,
      ratingAvg: (row['rating_avg'] as num?)?.toDouble() ?? 0,
      ratingCount: (row['rating_count'] as num?)?.toInt() ?? 0,
    ),
  );
}

VariantDraft _variantFromRow(Map<String, dynamic> v) {
  final price = switch (v['prices']) {
    final Map<String, dynamic> p => p,
    [final Map<String, dynamic> p, ...] => p,
    _ => null,
  };
  final stock = [
    for (final s in (v['stock'] as List? ?? const []))
      s as Map<String, dynamic>,
  ];
  return VariantDraft(
    id: v['id'] as String,
    sku: v['sku'] as String,
    barcode: v['barcode'] as String? ?? '',
    attributes: {
      for (final e in (v['attributes'] as Map? ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    },
    active: v['active'] != false,
    priceCents: (price?['amount_cents'] as num?)?.toInt(),
    compareAtCents: (price?['compare_at_cents'] as num?)?.toInt(),
    onHand: stock.fold(0, (sum, s) => sum + (s['qty'] as num).toInt()),
    reserved: stock.fold(0, (sum, s) => sum + (s['reserved'] as num).toInt()),
    lowStockAt: stock.isEmpty
        ? 0
        : (stock.first['low_stock_at'] as num).toInt(),
    stocked: stock.isNotEmpty,
  );
}

/// Specs are an ordered `[{"name","value"}]`; rows saved before F09 may be
/// an object (`{"model": "WH-PRO"}`).
List<Spec> specsFromJson(Object? json) => switch (json) {
  final List<dynamic> list => [
    for (final s in list)
      if (s is Map)
        Spec(
          name: s['name']?.toString() ?? '',
          value: s['value']?.toString() ?? '',
        ),
  ],
  final Map<dynamic, dynamic> map => [
    for (final e in map.entries)
      Spec(name: e.key.toString(), value: e.value.toString()),
  ],
  _ => const [],
};

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client, {Random? random})
    : _random = random ?? Random.secure();

  final SupabaseClient _client;
  final Random _random;

  static const bucket = 'product-images';

  String _imageUrl(String path) =>
      _client.storage.from(bucket).getPublicUrl(path);

  @override
  Future<CatalogPage> list(CatalogListQuery query) async {
    final data = await _client.rpc<dynamic>(
      'catalog_admin_list',
      params: {
        'p_tab': query.tab.name,
        'p_search': query.search.trim().isEmpty ? null : query.search.trim(),
        'p_category': query.categoryId,
        'p_stock': query.stock.wire,
        'p_quote_only': query.quoteOnly,
        'p_limit': CatalogListQuery.pageSize,
        'p_offset': query.page * CatalogListQuery.pageSize,
      },
    );
    final json = data as Map<String, dynamic>;
    return CatalogPage(
      rows: [
        for (final r in (json['rows'] as List? ?? const []))
          CatalogListItem.fromRow(
            r as Map<String, dynamic>,
            imageUrl: (p) => p == null ? null : _imageUrl(p),
          ),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      counts: CatalogPage.countsFromJson(json['counts']),
    );
  }

  @override
  Future<List<Category>> categories() async {
    final rows = await _client
        .from('categories')
        .select('id, parent_id, name, slug')
        .order('sort');
    return [for (final r in rows) Category.fromRow(r)];
  }

  @override
  Future<ProductDraft?> product(String id) async {
    final row = await _client
        .from('products')
        .select(productDraftSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : productDraftFromRow(row, imageUrl: _imageUrl);
  }

  @override
  Future<List<PriceChange>> priceHistory(String productId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'product_price_history',
      params: {'p_product': productId},
    );
    return [
      for (final r in rows) PriceChange.fromRow(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<ArchiveImpact> archiveImpact(String productId) async {
    final data = await _client.rpc<dynamic>(
      'catalog_archive_impact',
      params: {'p_product': productId},
    );
    return ArchiveImpact.fromJson(data as Map<String, dynamic>);
  }

  Future<CatalogOutcome> _manage(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('catalog-manage', body: body);
      return CatalogOutcome.fromJson(_json(res.data));
    } catch (e) {
      log('catalog-manage ${body['action']} failed: $e');
      return const CatalogRefused(CatalogRefusal.unknown);
    }
  }

  @override
  Future<CatalogOutcome> save(ProductDraft draft) =>
      _manage({'action': 'save', 'product': draft.toPayload()});

  @override
  Future<CatalogOutcome> archive(String id) =>
      _manage({'action': 'archive', 'id': id});

  @override
  Future<CatalogOutcome> restore(String id) =>
      _manage({'action': 'restore', 'id': id});

  @override
  Future<CatalogOutcome> archiveMany(List<String> ids) =>
      _manage({'action': 'bulk_archive', 'ids': ids});

  @override
  Future<CatalogOutcome> moveMany(List<String> ids, String categoryId) =>
      _manage({
        'action': 'bulk_category',
        'ids': ids,
        'category_id': categoryId,
      });

  @override
  Future<ImageDraft?> uploadImage({
    required String folder,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final path = productImagePath(folder, fileName, _random);
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: imageContentType(fileName)),
          );
      return ImageDraft(path: path, url: _imageUrl(path));
    } catch (e) {
      log('image upload failed: $e');
      return null;
    }
  }

  Future<ImportOutcome> _import(
    String action,
    String csv,
    Map<String, ImportField> mapping,
  ) async {
    try {
      final res = await _client.functions.invoke(
        'catalog-import',
        body: {
          'action': action,
          'csv': csv,
          'mapping': {for (final e in mapping.entries) e.key: e.value.wire},
        },
      );
      return ImportOutcome.fromJson(_json(res.data));
    } catch (e) {
      log('catalog-import $action failed: $e');
      return const ImportRefused(ImportRefusal.unknown);
    }
  }

  @override
  Future<ImportOutcome> previewImport(
    String csv,
    Map<String, ImportField> mapping,
  ) => _import('preview', csv, mapping);

  @override
  Future<ImportOutcome> commitImport(
    String csv,
    Map<String, ImportField> mapping,
  ) => _import('commit', csv, mapping);

  static Map<String, dynamic> _json(Object? data) =>
      (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;
}

/// No backend: an empty catalogue, every change refused.
class OfflineCatalogRepository implements CatalogRepository {
  const OfflineCatalogRepository();

  static const _offline = CatalogRefused(CatalogRefusal.unknown);

  @override
  Future<CatalogPage> list(CatalogListQuery query) async => const CatalogPage();
  @override
  Future<List<Category>> categories() async => const [];
  @override
  Future<ProductDraft?> product(String id) async => null;
  @override
  Future<List<PriceChange>> priceHistory(String productId) async => const [];
  @override
  Future<ArchiveImpact> archiveImpact(String productId) async =>
      const ArchiveImpact();
  @override
  Future<CatalogOutcome> save(ProductDraft draft) async => _offline;
  @override
  Future<CatalogOutcome> archive(String id) async => _offline;
  @override
  Future<CatalogOutcome> restore(String id) async => _offline;
  @override
  Future<CatalogOutcome> archiveMany(List<String> ids) async => _offline;
  @override
  Future<CatalogOutcome> moveMany(List<String> ids, String categoryId) async =>
      _offline;
  @override
  Future<ImageDraft?> uploadImage({
    required String folder,
    required String fileName,
    required Uint8List bytes,
  }) async => null;
  @override
  Future<ImportOutcome> previewImport(
    String csv,
    Map<String, ImportField> mapping,
  ) async => const ImportRefused(ImportRefusal.unknown);
  @override
  Future<ImportOutcome> commitImport(
    String csv,
    Map<String, ImportField> mapping,
  ) async => const ImportRefused(ImportRefusal.unknown);
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineCatalogRepository();
  }
  return SupabaseCatalogRepository(Supabase.instance.client);
});

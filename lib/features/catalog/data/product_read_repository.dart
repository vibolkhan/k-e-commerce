import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../domain/i18n_text.dart';
import '../domain/product_view.dart';

/// Products as customers read them, under their own RLS: only active
/// products and selling variants for shoppers, no prices for business
/// buyers. The admin Preview (A-05a) uses it so staff see what customers
/// will; the home, list and detail screens (F11, F13) build on it.
abstract interface class ProductReadRepository {
  Future<ProductView?> product(String id);
}

/// The `select` for one product with what a customer sees of it.
const productViewSelect =
    'id, slug, name, description, brand, rfq_enabled, rfq_min_qty, '
    'rating_avg, rating_count, '
    'product_images (path, alt, sort), '
    'product_variants (id, sku, attributes, sort, active, '
    'prices (amount_cents))';

/// Builds a [ProductView] from a [productViewSelect] row. [availability]
/// maps variant ids to what can still be ordered; [imageUrl] turns a storage
/// path into a public URL.
ProductView productViewFromRow(
  Map<String, dynamic> row, {
  required String Function(String path) imageUrl,
  Map<String, int> availability = const {},
}) {
  final images = [...(row['product_images'] as List? ?? const [])]
    ..sort(
      (a, b) =>
          ((a as Map)['sort'] as num).compareTo((b as Map)['sort'] as num),
    );
  final variants = [...(row['product_variants'] as List? ?? const [])]
    ..sort(
      (a, b) =>
          ((a as Map)['sort'] as num).compareTo((b as Map)['sort'] as num),
    );
  return ProductView(
    id: row['id'] as String,
    slug: row['slug'] as String,
    name: I18nText.fromJson(row['name']),
    description: I18nText.fromJson(row['description']),
    brand: row['brand'] as String?,
    imageUrls: [for (final i in images) imageUrl((i as Map)['path'] as String)],
    imageAlts: [for (final i in images) I18nText.fromJson((i as Map)['alt'])],
    variants: [
      for (final v in variants.cast<Map<String, dynamic>>())
        if (v['active'] != false)
          VariantView(
            id: v['id'] as String,
            sku: v['sku'] as String,
            attributes: {
              for (final e in (v['attributes'] as Map? ?? const {}).entries)
                e.key.toString(): e.value.toString(),
            },
            priceCents: switch (v['prices']) {
              {'amount_cents': final num n} => n.toInt(),
              [{'amount_cents': final num n}, ...] => n.toInt(),
              _ => null,
            },
            available: availability[v['id']] ?? 0,
          ),
    ],
    rfqEnabled: row['rfq_enabled'] == true,
    rfqMinQty: (row['rfq_min_qty'] as num?)?.toInt(),
    ratingAvg: (row['rating_avg'] as num?)?.toDouble() ?? 0,
    ratingCount: (row['rating_count'] as num?)?.toInt() ?? 0,
  );
}

class SupabaseProductReadRepository implements ProductReadRepository {
  SupabaseProductReadRepository(this._client);

  final SupabaseClient _client;

  String _imageUrl(String path) =>
      _client.storage.from('product-images').getPublicUrl(path);

  @override
  Future<ProductView?> product(String id) async {
    final row = await _client
        .from('products')
        .select(productViewSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final stock = await _client
        .from('variant_availability')
        .select('variant_id, available')
        .eq('product_id', id);
    return productViewFromRow(
      row,
      imageUrl: _imageUrl,
      availability: {
        for (final s in stock)
          s['variant_id'] as String: (s['available'] as num).toInt(),
      },
    );
  }
}

class OfflineProductReadRepository implements ProductReadRepository {
  const OfflineProductReadRepository();

  @override
  Future<ProductView?> product(String id) async => null;
}

final productReadRepositoryProvider = Provider<ProductReadRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineProductReadRepository();
  }
  return SupabaseProductReadRepository(Supabase.instance.client);
});

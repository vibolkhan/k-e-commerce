import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../domain/product_detail.dart';
import '../domain/reviews.dart';

/// The product page (C-05), read under the viewer's RLS through
/// `product_detail`: null for a product that isn't on sale.
abstract interface class ProductDetailRepository {
  Future<ProductDetail?> detail(String id);
}

class SupabaseProductDetailRepository implements ProductDetailRepository {
  SupabaseProductDetailRepository(this._client);

  final SupabaseClient _client;

  String _productImage(String path) =>
      _client.storage.from('product-images').getPublicUrl(path);

  @override
  Future<ProductDetail?> detail(String id) async {
    final json = await _client.rpc<Map<String, dynamic>?>(
      'product_detail',
      params: {'p_id': id},
    );
    if (json == null) return null;
    return ProductDetail.fromJson(json, imageUrl: _productImage);
  }
}

class OfflineProductDetailRepository implements ProductDetailRepository {
  const OfflineProductDetailRepository();

  @override
  Future<ProductDetail?> detail(String id) async => null;
}

final productDetailRepositoryProvider = Provider<ProductDetailRepository>((
  ref,
) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineProductDetailRepository();
  }
  return SupabaseProductDetailRepository(Supabase.instance.client);
});

/// Published reviews for the Reviews tab (C-05b). Reading them, with
/// reviewer names, is F32; until then there are none to show.
abstract interface class ReviewsRepository {
  Future<ProductReviews> reviews(String productId);
}

class PendingReviewsRepository implements ReviewsRepository {
  const PendingReviewsRepository();

  @override
  Future<ProductReviews> reviews(String productId) async => ProductReviews.none;
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>(
  (ref) => const PendingReviewsRepository(),
);

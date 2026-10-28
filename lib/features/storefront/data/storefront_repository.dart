import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../catalog/domain/i18n_text.dart';
import '../domain/browse.dart';
import '../domain/storefront.dart';

/// What shoppers browse (C-01 – C-03), read under their own RLS: guests and
/// customers see retail prices, business buyers none. Banners and
/// collections are filtered to the viewer's audience here and in
/// `catalog_browse`, since RLS does not look at audience.
abstract interface class StorefrontRepository {
  /// Active categories, every level.
  Future<List<StoreCategory>> categories();

  /// Live banners for [audience], in A-12 order.
  Future<List<HomeBanner>> banners(Audience audience);

  /// One page of products (`catalog_browse`).
  Future<BrowsePage> browse(BrowseQuery query);

  /// A collection's title, or null when it doesn't exist or isn't live.
  Future<I18nText?> collectionTitle(String slug);

  /// The server clock, cut-off and holidays. [deviceNow] is when the call
  /// was made, to turn the server time into an offset.
  Future<StoreClock> clock(DateTime deviceNow);

  /// The signed-in shopper's saved addresses, default first. Empty for
  /// guests.
  Future<List<DeliverTo>> addresses();
}

class SupabaseStorefrontRepository implements StorefrontRepository {
  SupabaseStorefrontRepository(this._client);

  final SupabaseClient _client;

  String _productImage(String path) =>
      _client.storage.from('product-images').getPublicUrl(path);

  String _bannerImage(String path) =>
      _client.storage.from('banners').getPublicUrl(path);

  @override
  Future<List<StoreCategory>> categories() async {
    final rows = await _client
        .from('categories')
        .select('id, parent_id, slug, name, icon, banner_path, sort')
        .eq('active', true)
        .order('sort');
    return [
      for (final r in rows) StoreCategory.fromRow(r, bannerUrl: _bannerImage),
    ];
  }

  @override
  Future<List<HomeBanner>> banners(Audience audience) async {
    final rows = await _client
        .from('banners')
        .select(
          'id, title, subtitle, cta, badge, image_path, link_type, '
          'link_target',
        )
        .inFilter('audience', audience.visible)
        .order('sort');
    return [
      for (final r in rows) HomeBanner.fromRow(r, imageUrl: _bannerImage),
    ];
  }

  @override
  Future<BrowsePage> browse(BrowseQuery query) async {
    final json = await _client.rpc<Map<String, dynamic>>(
      'catalog_browse',
      params: query.toRpcParams(),
    );
    return BrowsePage.fromJson(json, imageUrl: _productImage);
  }

  @override
  Future<I18nText?> collectionTitle(String slug) async {
    final row = await _client
        .from('collections')
        .select('title')
        .eq('slug', slug)
        .maybeSingle();
    return row == null ? null : I18nText.fromJson(row['title']);
  }

  @override
  Future<StoreClock> clock(DateTime deviceNow) async {
    final json = await _client.rpc<Map<String, dynamic>>('storefront_clock');
    return StoreClock.fromJson(json, deviceNow);
  }

  @override
  Future<List<DeliverTo>> addresses() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    // Support staff may read every address; the pill wants only our own.
    final rows = await _client
        .from('addresses')
        .select('id, label, is_default, zone:delivery_zones (name)')
        .eq('profile_id', user.id)
        .order('is_default', ascending: false)
        .order('created_at');
    return [
      for (final r in rows)
        DeliverTo(
          id: r['id'] as String,
          label: r['label'] as String? ?? '',
          area: (r['zone'] as Map?)?['name'] as String?,
        ),
    ];
  }
}

/// No Supabase config: an empty shop.
class OfflineStorefrontRepository implements StorefrontRepository {
  const OfflineStorefrontRepository();

  @override
  Future<List<StoreCategory>> categories() async => const [];

  @override
  Future<List<HomeBanner>> banners(Audience audience) async => const [];

  @override
  Future<BrowsePage> browse(BrowseQuery query) async => BrowsePage.empty;

  @override
  Future<I18nText?> collectionTitle(String slug) async => null;

  @override
  Future<StoreClock> clock(DateTime deviceNow) async =>
      StoreClock.local(deviceNow);

  @override
  Future<List<DeliverTo>> addresses() async => const [];
}

final storefrontRepositoryProvider = Provider<StorefrontRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineStorefrontRepository();
  }
  return SupabaseStorefrontRepository(Supabase.instance.client);
});

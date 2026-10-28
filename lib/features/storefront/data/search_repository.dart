import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../domain/search.dart';
import '../domain/storefront.dart';
import 'recent_search_store.dart';

/// Search (C-04) besides the results themselves, which come from
/// `catalog_browse` through [StorefrontRepository.browse].
abstract interface class SearchRepository {
  /// Words, "… in Category" and products for what is being typed; empty
  /// before [minSuggestChars] characters.
  Future<SearchSuggestions> suggest(String query);

  /// The corrected query for a search that found nothing, if one finds
  /// products ("hedfones" → "headphones").
  Future<String?> didYouMean(String query);

  /// Best-selling categories, for the chips on C-04 and C-04b.
  Future<List<StoreCategory>> popularCategories();

  /// Most recent first: the account's when signed in, else this device's.
  Future<List<String>> recentSearches();

  /// Logs a finished search with its result count and how long it took,
  /// and adds it to the recent searches.
  Future<void> recordSearch(
    String query, {
    required int results,
    required Duration took,
  });

  Future<void> clearRecentSearches();
}

class SupabaseSearchRepository implements SearchRepository {
  SupabaseSearchRepository(this._client, this._device);

  final SupabaseClient _client;
  final RecentSearchStore _device;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<SearchSuggestions> suggest(String query) async {
    if (normalizeSearch(query).length < minSuggestChars) {
      return SearchSuggestions.empty;
    }
    final json = await _client.rpc<Map<String, dynamic>>(
      'catalog_suggest',
      params: {'p_q': query},
    );
    return SearchSuggestions.fromJson(
      json,
      imageUrl: (path) =>
          _client.storage.from('product-images').getPublicUrl(path),
    );
  }

  @override
  Future<String?> didYouMean(String query) =>
      _client.rpc<String?>('search_did_you_mean', params: {'p_q': query});

  @override
  Future<List<StoreCategory>> popularCategories() async {
    final rows = await _client.rpc<List<dynamic>>('popular_categories');
    return [
      for (final r in rows)
        StoreCategory.fromRow(
          r as Map<String, dynamic>,
          bannerUrl: (path) =>
              _client.storage.from('banners').getPublicUrl(path),
        ),
    ];
  }

  @override
  Future<List<String>> recentSearches() async {
    final uid = _uid;
    if (uid == null) return _device.read().take(recentSearchLimit).toList();
    final rows = await _client
        .from('search_history')
        .select('query')
        .eq('profile_id', uid)
        .order('searched_at', ascending: false)
        .limit(recentSearchLimit);
    return [for (final r in rows) r['query'] as String];
  }

  @override
  Future<void> recordSearch(
    String query, {
    required int results,
    required Duration took,
  }) async {
    if (_uid == null) await _device.push(query);
    await _client.rpc<void>(
      'record_search',
      params: {
        'p_query': query,
        'p_results': results,
        'p_took_ms': took.inMilliseconds,
      },
    );
  }

  @override
  Future<void> clearRecentSearches() async {
    final uid = _uid;
    if (uid == null) return _device.clear();
    await _client.from('search_history').delete().eq('profile_id', uid);
  }
}

/// No Supabase config: nothing to find, but recent searches still work on
/// the device.
class OfflineSearchRepository implements SearchRepository {
  const OfflineSearchRepository(this._device);

  final RecentSearchStore _device;

  @override
  Future<SearchSuggestions> suggest(String query) async =>
      SearchSuggestions.empty;

  @override
  Future<String?> didYouMean(String query) async => null;

  @override
  Future<List<StoreCategory>> popularCategories() async => const [];

  @override
  Future<List<String>> recentSearches() async =>
      _device.read().take(recentSearchLimit).toList();

  @override
  Future<void> recordSearch(
    String query, {
    required int results,
    required Duration took,
  }) => _device.push(query);

  @override
  Future<void> clearRecentSearches() => _device.clear();
}

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final device = ref.watch(recentSearchStoreProvider);
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return OfflineSearchRepository(device);
  }
  return SupabaseSearchRepository(Supabase.instance.client, device);
});

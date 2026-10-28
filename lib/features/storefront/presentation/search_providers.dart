import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/log.dart';
import '../data/search_repository.dart';
import '../domain/storefront.dart';
import 'storefront_providers.dart';

/// Chips on C-04 and C-04b: the best-selling categories, or the top of the
/// tree when those can't be read.
final popularCategoriesProvider = FutureProvider<List<StoreCategory>>((
  ref,
) async {
  try {
    final popular = await ref
        .watch(searchRepositoryProvider)
        .popularCategories();
    if (popular.isNotEmpty) return popular;
  } catch (e) {
    log('Could not load popular categories: $e');
  }
  final tree = await ref.watch(storeCategoriesProvider.future);
  return tree.top.take(6).toList();
});

/// [viewer]'s recent searches (null: this device's, as a guest). A new
/// viewer is a new family member, as with the storefront providers.
final recentSearchesProvider = FutureProvider.family<List<String>, String?>((
  ref,
  viewer,
) async {
  try {
    return await ref.watch(searchRepositoryProvider).recentSearches();
  } catch (e) {
    log('Could not load recent searches: $e');
    return const [];
  }
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/domain/staff_permissions.dart';
import '../../admin/presentation/admin_providers.dart';
import '../data/catalog_repository.dart';
import '../data/product_read_repository.dart';
import '../domain/catalog_list.dart';
import '../domain/product_draft.dart';
import '../domain/product_view.dart';

/// Whether the signed-in staff member may change products (A-14d "Full":
/// super admin and catalog). Sales and support only look.
final canEditCatalogProvider = Provider<bool>((ref) {
  final role = ref.watch(currentStaffRoleProvider);
  return role != null && canEdit(role, PermissionArea.products);
});

/// A-05 tab, search, filters and page.
class CatalogQueryController extends Notifier<CatalogListQuery> {
  @override
  CatalogListQuery build() => const CatalogListQuery();

  void update(CatalogListQuery Function(CatalogListQuery) change) =>
      state = change(state);

  void clearFilters() => state = CatalogListQuery(tab: state.tab);
}

final catalogQueryProvider =
    NotifierProvider<CatalogQueryController, CatalogListQuery>(
      CatalogQueryController.new,
    );

final catalogPageProvider = FutureProvider.autoDispose<CatalogPage>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .list(ref.watch(catalogQueryProvider)),
);

final catalogCategoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

/// The saved product the editor starts from; null when it doesn't exist.
final productDraftProvider = FutureProvider.autoDispose
    .family<ProductDraft?, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
    );

final priceHistoryProvider = FutureProvider.autoDispose
    .family<List<PriceChange>, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).priceHistory(id),
    );

/// The product as customers read it (Preview).
final productViewProvider = FutureProvider.autoDispose
    .family<ProductView?, String>(
      (ref, id) => ref.watch(productReadRepositoryProvider).product(id),
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/domain/staff_permissions.dart';
import '../../admin/presentation/admin_providers.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory.dart';

/// Whether the signed-in staff member may adjust stock (A-14d "Products &
/// inventory" Full: super admin and catalog). Sales and support only look.
final canAdjustStockProvider = Provider<bool>((ref) {
  final role = ref.watch(currentStaffRoleProvider);
  return role != null && canEdit(role, PermissionArea.products);
});

/// A-06 filter, search and page.
class InventoryQueryController extends Notifier<InventoryQuery> {
  @override
  InventoryQuery build() => const InventoryQuery();

  void update(InventoryQuery Function(InventoryQuery) change) =>
      state = change(state);
}

final inventoryQueryProvider =
    NotifierProvider<InventoryQueryController, InventoryQuery>(
      InventoryQueryController.new,
    );

final inventoryPageProvider = FutureProvider.autoDispose<InventoryPage>(
  (ref) => ref
      .watch(inventoryRepositoryProvider)
      .list(ref.watch(inventoryQueryProvider)),
);

/// Recent movements of one variant, or of every variant when null.
final stockHistoryProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, String?>(
      (ref, variantId) => ref
          .watch(inventoryRepositoryProvider)
          .history(variantId: variantId, limit: variantId == null ? 50 : 10),
    );

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/utils/log.dart';
import '../domain/inventory.dart';

/// Back-office stock (F10). Reads go through staff-only RPCs; every change
/// goes through the inventory-manage Edge Function, which writes as the
/// staff member so the change lands in audit_logs under their name.
abstract interface class InventoryRepository {
  Future<InventoryPage> list(InventoryQuery query);

  /// Stock movements, newest first, for one variant or (null) every variant.
  Future<List<StockMovement>> history({String? variantId, int limit = 30});

  /// [reasonLabel]: the chosen reason as staff read it, kept with the note
  /// when the ledger reason alone can't tell it apart.
  Future<InventoryOutcome> adjust(
    StockAdjustment adjustment, {
    String? reasonLabel,
  });
}

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository(this._client);

  final SupabaseClient _client;

  String? _imageUrl(String? path) => path == null
      ? null
      : _client.storage.from('product-images').getPublicUrl(path);

  @override
  Future<InventoryPage> list(InventoryQuery query) async {
    final data = await _client.rpc<dynamic>(
      'inventory_admin_list',
      params: {
        'p_search': query.search.trim().isEmpty ? null : query.search.trim(),
        'p_filter': query.filter.name,
        'p_limit': InventoryQuery.pageSize,
        'p_offset': query.page * InventoryQuery.pageSize,
      },
    );
    final json = data as Map<String, dynamic>;
    return InventoryPage(
      rows: [
        for (final r in (json['rows'] as List? ?? const []))
          InventoryRow.fromRow(r as Map<String, dynamic>, imageUrl: _imageUrl),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      summary: InventorySummary.fromJson(json['summary']),
      counts: InventoryPage.countsFromJson(json['counts']),
    );
  }

  @override
  Future<List<StockMovement>> history({
    String? variantId,
    int limit = 30,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'stock_history',
      params: {'p_variant': variantId, 'p_limit': limit},
    );
    return [
      for (final r in rows) StockMovement.fromRow(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<InventoryOutcome> adjust(
    StockAdjustment adjustment, {
    String? reasonLabel,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'inventory-manage',
        body: adjustment.toPayload(reasonLabel: reasonLabel),
      );
      final data = res.data;
      return InventoryOutcome.fromJson(
        (data is String ? jsonDecode(data) : data) as Map<String, dynamic>,
      );
    } catch (e) {
      log('inventory-manage adjust failed: $e');
      return const InventoryRefused(InventoryRefusal.unknown);
    }
  }
}

/// No backend configured: nothing to show, nothing saved.
class OfflineInventoryRepository implements InventoryRepository {
  const OfflineInventoryRepository();

  @override
  Future<InventoryPage> list(InventoryQuery query) async =>
      const InventoryPage();

  @override
  Future<List<StockMovement>> history({
    String? variantId,
    int limit = 30,
  }) async => const [];

  @override
  Future<InventoryOutcome> adjust(
    StockAdjustment adjustment, {
    String? reasonLabel,
  }) async => const InventoryRefused(InventoryRefusal.unknown);
}

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineInventoryRepository();
  }
  return SupabaseInventoryRepository(Supabase.instance.client);
});

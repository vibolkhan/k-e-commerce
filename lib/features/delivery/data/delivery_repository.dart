import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../domain/delivery.dart';

abstract interface class DeliveryRepository {
  Future<List<DeliveryAddress>> addresses();
  Future<void> saveAddress(AddressDraft draft);
  Future<void> deleteAddress(String id);
  Future<void> setDefault(String id);
  Future<DeliveryQuote> quote(String addressId, int subtotalCents);
  Future<List<DeliveryZone>> zones();
  Future<void> saveZone(DeliveryZone zone);
}

class SupabaseDeliveryRepository implements DeliveryRepository {
  SupabaseDeliveryRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<DeliveryAddress>> addresses() async {
    final rows = await _client
        .from('addresses')
        .select('*, delivery_zones(name)')
        .order('is_default', ascending: false)
        .order('created_at');
    return [for (final row in rows) DeliveryAddress.fromRow(row)];
  }

  @override
  Future<void> saveAddress(AddressDraft draft) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign-in required');
    final values = {
      'profile_id': user.id,
      'label': draft.label,
      'line': draft.line,
      'city': draft.city,
      'lat': draft.point.lat,
      'lng': draft.point.lng,
      'recipient_name': draft.recipientName,
      'phone': draft.phone,
      'note': draft.note,
      'is_default': draft.isDefault,
    };
    if (draft.id == null) {
      await _client.from('addresses').insert(values);
    } else {
      await _client.from('addresses').update(values).eq('id', draft.id!);
    }
  }

  @override
  Future<void> deleteAddress(String id) =>
      _client.from('addresses').delete().eq('id', id);

  @override
  Future<void> setDefault(String id) =>
      _client.from('addresses').update({'is_default': true}).eq('id', id);

  @override
  Future<DeliveryQuote> quote(String addressId, int subtotalCents) async {
    final result = await _client.functions.invoke(
      'quote-delivery',
      body: {'address_id': addressId, 'subtotal_cents': subtotalCents},
    );
    final data = result.data is String
        ? jsonDecode(result.data as String)
        : result.data;
    return DeliveryQuote.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<List<DeliveryZone>> zones() async {
    final raw = await _client.rpc<dynamic>('delivery_zone_directory');
    final rows = raw as List<dynamic>? ?? const [];
    return [
      for (final row in rows) DeliveryZone.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> saveZone(DeliveryZone zone) async {
    final result = await _client.functions.invoke(
      'delivery-zone-manage',
      body: {
        'action': 'save',
        'id': zone.id,
        'name': zone.name,
        'polygon': zone.polygonJson,
        'fee_cents': zone.feeCents,
        'free_threshold_cents': zone.freeThresholdCents,
        'same_day': zone.sameDay,
        'cod_enabled': zone.codEnabled,
        'cod_limit_cents': zone.codLimitCents,
        'active': zone.active,
      },
    );
    final data = result.data is String
        ? jsonDecode(result.data as String)
        : result.data;
    if (data is! Map || data['status'] != 'saved') {
      throw StateError('Zone save failed: $data');
    }
  }
}

class OfflineDeliveryRepository implements DeliveryRepository {
  OfflineDeliveryRepository();
  final _addresses = <DeliveryAddress>[];
  final _zones = <DeliveryZone>[];

  @override
  Future<List<DeliveryAddress>> addresses() async => List.unmodifiable(_addresses);
  @override
  Future<void> deleteAddress(String id) async =>
      _addresses.removeWhere((a) => a.id == id);
  @override
  Future<void> saveAddress(AddressDraft draft) async {}
  @override
  Future<void> setDefault(String id) async {}
  @override
  Future<DeliveryQuote> quote(String addressId, int subtotalCents) async =>
      const OutOfZoneDeliveryQuote();
  @override
  Future<List<DeliveryZone>> zones() async => List.unmodifiable(_zones);
  @override
  Future<void> saveZone(DeliveryZone zone) async {}
}

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return OfflineDeliveryRepository();
  }
  return SupabaseDeliveryRepository(Supabase.instance.client);
});

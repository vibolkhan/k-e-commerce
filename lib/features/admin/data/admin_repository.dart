import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/utils/log.dart';
import '../domain/admin_section.dart';
import '../domain/staff_member.dart';
import '../domain/staff_outcome.dart';
import '../domain/staff_role.dart';

/// Back-office data the shell and A-14d need. Staff changes go through the
/// staff-manage Edge Function; reads run under the caller's RLS.
abstract interface class AdminRepository {
  /// Sidebar counts per section (`admin_badge_counts()`); sections the
  /// caller can't see count 0.
  Future<Map<AdminSection, int>> badgeCounts();

  /// A-14d list (`staff_directory()`); super admins only.
  Future<List<StaffMember>> staffDirectory();

  Future<StaffOutcome> invite({
    required String fullName,
    required String contact,
    required StaffRole role,
  });
  Future<StaffOutcome> resend(String profileId);
  Future<StaffOutcome> updateRole(String profileId, StaffRole role);
  Future<StaffOutcome> remove(String profileId);
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<AdminSection, int>> badgeCounts() async {
    final data = await _client.rpc<dynamic>('admin_badge_counts');
    final counts = data is Map ? data : const {};
    return {
      for (final section in AdminSection.values)
        if (counts[section.name] case final num n when n > 0)
          section: n.toInt(),
    };
  }

  @override
  Future<List<StaffMember>> staffDirectory() async {
    final rows = await _client.rpc<List<dynamic>>('staff_directory');
    return [
      for (final row in rows) StaffMember.fromRow(row as Map<String, dynamic>),
    ];
  }

  Future<StaffOutcome> _manage(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke('staff-manage', body: body);
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      return StaffOutcome.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      log('staff-manage ${body['action']} failed: $e');
      return const StaffRefused(StaffRefusal.unknown);
    }
  }

  @override
  Future<StaffOutcome> invite({
    required String fullName,
    required String contact,
    required StaffRole role,
  }) => _manage({
    'action': 'invite',
    'full_name': fullName,
    'contact': contact,
    'role': role.dbName,
  });

  @override
  Future<StaffOutcome> resend(String profileId) =>
      _manage({'action': 'resend', 'profile_id': profileId});

  @override
  Future<StaffOutcome> updateRole(String profileId, StaffRole role) => _manage({
    'action': 'update_role',
    'profile_id': profileId,
    'role': role.dbName,
  });

  @override
  Future<StaffOutcome> remove(String profileId) =>
      _manage({'action': 'remove', 'profile_id': profileId});
}

/// No backend: no counts, no staff, every change refused.
class OfflineAdminRepository implements AdminRepository {
  const OfflineAdminRepository();

  static const _offline = StaffRefused(StaffRefusal.unknown);

  @override
  Future<Map<AdminSection, int>> badgeCounts() async => const {};

  @override
  Future<List<StaffMember>> staffDirectory() async => const [];

  @override
  Future<StaffOutcome> invite({
    required String fullName,
    required String contact,
    required StaffRole role,
  }) async => _offline;

  @override
  Future<StaffOutcome> resend(String profileId) async => _offline;

  @override
  Future<StaffOutcome> updateRole(String profileId, StaffRole role) async =>
      _offline;

  @override
  Future<StaffOutcome> remove(String profileId) async => _offline;
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineAdminRepository();
  }
  return SupabaseAdminRepository(Supabase.instance.client);
});

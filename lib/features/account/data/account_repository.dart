import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/utils/log.dart';
import '../domain/delete_account_outcome.dart';

/// The signed-in user's own account: S-08b edits and AUTH-07 deletion.
abstract interface class AccountRepository {
  /// Saves the name and contact email (null clears it). The phone is set by
  /// sign-in only.
  Future<void> updateProfile({required String fullName, String? email});

  /// Asks the server to delete the account. Does not sign out locally.
  Future<DeleteAccountOutcome> deleteAccount({String? reason});
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> updateProfile({required String fullName, String? email}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not signed in');
    await _client
        .from('profiles')
        .update({'full_name': fullName.trim(), 'email': email})
        .eq('id', userId);
  }

  @override
  Future<DeleteAccountOutcome> deleteAccount({String? reason}) async {
    try {
      final res = await _client.functions.invoke(
        'account-delete',
        body: {'reason': ?reason},
      );
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      return switch ((data as Map)['status']) {
        'deleted' => const AccountDeleted(),
        'has_active_orders' => const HasActiveOrders(),
        'not_allowed' => const DeleteNotAllowed(),
        final other => DeleteFailed('Unexpected status $other'),
      };
    } catch (e) {
      log('account-delete failed: $e');
      return DeleteFailed(e);
    }
  }
}

/// No backend: guests only, so there is nothing to edit or delete.
class OfflineAccountRepository implements AccountRepository {
  const OfflineAccountRepository();

  @override
  Future<void> updateProfile({required String fullName, String? email}) =>
      Future.error(StateError('Supabase not configured'));

  @override
  Future<DeleteAccountOutcome> deleteAccount({String? reason}) async =>
      const DeleteFailed('Supabase not configured');
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const OfflineAccountRepository();
  }
  return SupabaseAccountRepository(Supabase.instance.client);
});

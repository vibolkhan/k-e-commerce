import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/bootstrap.dart';
import '../data/auth_repository.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_outcome.dart';
import '../domain/profile.dart';

/// Supabase when configured; otherwise an offline stand-in (dev without
/// keys, tests) where everyone is a guest. Tests override this.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.isSupabaseConfigured) return const OfflineAuthRepository();
  return SupabaseAuthRepository(Supabase.instance.client, config);
});

/// Signed-in user id; null for guests.
final authUserIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(authRepositoryProvider).userIdChanges(),
);

/// The signed-in user's profile; null for guests (and while loading).
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = await ref.watch(authUserIdProvider.future);
  if (userId == null) return null;
  return ref.watch(authRepositoryProvider).fetchProfile();
});

/// Opens Contact support from S-06b. Support chat arrives with its own task;
/// until then the default shows a short notice (see `blocked_dialog.dart`).
final contactSupportProvider = Provider<void Function()?>((ref) => null);

/// No backend: every sign-in attempt fails as if offline.
class OfflineAuthRepository implements AuthRepository {
  const OfflineAuthRepository();

  static const _offline = AuthFailure('Supabase not configured');

  @override
  String? get currentUserId => null;

  @override
  Stream<String?> userIdChanges() => Stream.value(null);

  @override
  Future<AuthOutcome> sendOtp(String phone) async => _offline;

  @override
  Future<AuthOutcome> verifyOtp(String phone, String code) async => _offline;

  @override
  Future<AuthOutcome> signInWithPassword(String email, String password) async =>
      _offline;

  @override
  Future<AuthOutcome> signUpWithPassword(String email, String password) async =>
      _offline;

  @override
  Future<AuthOutcome> resetPassword(String email) async => _offline;

  @override
  Future<AuthOutcome> signInWithGoogle() async => _offline;

  @override
  Future<AuthOutcome> signInWithApple() async => _offline;

  @override
  Future<AuthOutcome> setPassword(String password) async => _offline;

  @override
  Future<Profile?> fetchProfile() async => null;

  @override
  Future<void> completeProfile({
    required String fullName,
    String? email,
    required bool emailReceipts,
  }) async {}

  @override
  Future<void> signOut() async {}
}

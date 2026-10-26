import 'package:k_e_commerce/features/account/data/account_repository.dart';
import 'package:k_e_commerce/features/account/domain/delete_account_outcome.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';

import '../auth/fake_auth_repository.dart';

/// Edits and deletes accounts held by a [FakeAuthRepository], so the
/// profile the app reloads reflects the change. [nextDelete] scripts the
/// server's answer.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this.auth);

  final FakeAuthRepository auth;
  DeleteAccountOutcome nextDelete = const AccountDeleted();
  final deleteReasons = <String?>[];
  var updates = 0;

  String get _key => auth.accounts.entries
      .firstWhere((e) => e.value.id == auth.currentUserId)
      .key;

  @override
  Future<void> updateProfile({required String fullName, String? email}) async {
    updates++;
    final old = auth.accounts[_key]!;
    auth.accounts[_key] = Profile(
      id: old.id,
      role: old.role,
      fullName: fullName,
      email: email,
      phone: old.phone,
    );
  }

  @override
  Future<DeleteAccountOutcome> deleteAccount({String? reason}) async {
    deleteReasons.add(reason);
    if (nextDelete is AccountDeleted) auth.accounts.remove(_key);
    return nextDelete;
  }
}

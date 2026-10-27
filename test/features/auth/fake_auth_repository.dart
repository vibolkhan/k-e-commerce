import 'dart:async';

import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/features/auth/data/auth_repository.dart';
import 'package:k_e_commerce/features/auth/domain/auth_outcome.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';

/// In-memory stand-in for Supabase Auth + the auth-* Edge Functions, with
/// the same rules: 5 wrong tries lock for 15 minutes, a code can be resent
/// after 60 s, blocked accounts never get a session.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.goodCode = '123456',
    this.goodPassword = 'password123',
    Map<String, Profile>? accounts,
  }) : accounts = accounts ?? {};

  final String goodCode;
  final String goodPassword;

  /// Keyed by E.164 phone or lower-case email.
  final Map<String, Profile> accounts;

  final _userIds = StreamController<String?>.broadcast();
  String? _userId;
  final _failures = <String, int>{};
  final _lockedUntil = <String, DateTime>{};

  /// What the next sendOtp/verifyOtp returns instead of the rules, once.
  AuthOutcome? nextSend;
  AuthOutcome? nextVerify;
  AuthOutcome? nextSocial;

  final sentTo = <String>[];
  final resetEmails = <String>[];
  var signOuts = 0;
  ({String fullName, String? email, bool emailReceipts})? completed;

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> userIdChanges() async* {
    yield _userId;
    yield* _userIds.stream;
  }

  void _signIn(String id) {
    _userId = id;
    _userIds.add(id);
  }

  Profile _account(String key) => accounts.putIfAbsent(
    key,
    () => Profile(id: 'new-$key', role: AppRole.customer),
  );

  Locked? _lock(String key) {
    final until = _lockedUntil[key];
    if (until == null) return null;
    if (until.isBefore(DateTime.now())) {
      _lockedUntil.remove(key);
      _failures.remove(key);
      return null;
    }
    return Locked(until);
  }

  AuthOutcome _fail(String key) {
    final failures = (_failures[key] ?? 0) + 1;
    _failures[key] = failures;
    if (failures >= 5) {
      final until = DateTime.now().add(const Duration(minutes: 15));
      _lockedUntil[key] = until;
      return Locked(until);
    }
    return WrongCredentials(5 - failures);
  }

  AuthOutcome _success(String key) {
    _failures.remove(key);
    final account = _account(key);
    if (account.isBlocked) return const Blocked();
    _signIn(account.id);
    return SignedIn(isNewUser: account.needsName);
  }

  @override
  Future<AuthOutcome> sendOtp(String phone) async {
    final scripted = nextSend;
    nextSend = null;
    if (scripted != null) return scripted;
    final locked = _lock(phone);
    if (locked != null) return locked;
    if (accounts[phone]?.isBlocked ?? false) return const Blocked();
    sentTo.add(phone);
    return const OtpSent(Duration(seconds: 60));
  }

  @override
  Future<AuthOutcome> verifyOtp(String phone, String code) async {
    final scripted = nextVerify;
    nextVerify = null;
    if (scripted != null) return scripted;
    final locked = _lock(phone);
    if (locked != null) return locked;
    return code == goodCode ? _success(phone) : _fail(phone);
  }

  @override
  Future<AuthOutcome> signInWithPassword(String email, String password) async {
    final locked = _lock(email);
    if (locked != null) return locked;
    if (!accounts.containsKey(email)) return _fail(email);
    return password == goodPassword ? _success(email) : _fail(email);
  }

  @override
  Future<AuthOutcome> signUpWithPassword(String email, String password) async {
    if (accounts.containsKey(email)) return const EmailInUse();
    return _success(email);
  }

  @override
  Future<AuthOutcome> resetPassword(String email) async {
    resetEmails.add(email);
    return const OtpSent(Duration.zero);
  }

  @override
  Future<AuthOutcome> signInWithGoogle() async => _social('google');

  @override
  Future<AuthOutcome> signInWithApple() async => _social('apple');

  AuthOutcome _social(String key) {
    final scripted = nextSocial;
    nextSocial = null;
    return scripted ?? _success(key);
  }

  final passwordsSet = <String>[];

  @override
  Future<AuthOutcome> setPassword(String password) async {
    passwordsSet.add(password);
    final key = accounts.entries.firstWhere((e) => e.value.id == _userId).key;
    final old = accounts[key]!;
    accounts[key] = Profile(
      id: old.id,
      role: old.role,
      fullName: old.fullName,
      email: old.email,
      phone: old.phone,
      staffRole: old.staffRole,
      staffStatus: old.staffStatus,
    );
    return const SignedIn(isNewUser: false);
  }

  @override
  Future<Profile?> fetchProfile() async {
    for (final account in accounts.values) {
      if (account.id == _userId) return account;
    }
    return null;
  }

  @override
  Future<void> completeProfile({
    required String fullName,
    String? email,
    required bool emailReceipts,
  }) async {
    completed = (
      fullName: fullName,
      email: email,
      emailReceipts: emailReceipts,
    );
    final key = accounts.entries.firstWhere((e) => e.value.id == _userId).key;
    final old = accounts[key]!;
    accounts[key] = Profile(
      id: old.id,
      role: old.role,
      fullName: fullName,
      email: email ?? old.email,
      phone: old.phone,
      staffRole: old.staffRole,
      staffStatus: old.staffStatus,
    );
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _userId = null;
    _userIds.add(null);
  }

  Future<void> dispose() => _userIds.close();
}

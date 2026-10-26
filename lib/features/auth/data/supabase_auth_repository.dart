import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/log.dart';
import '../../notifications/domain/notification_prefs.dart';
import '../domain/auth_outcome.dart';
import '../domain/profile.dart';
import 'auth_repository.dart';

/// Phone and email go through the auth-* Edge Functions, which count wrong
/// tries and refuse blocked accounts; the session they return is installed
/// locally. Google and Apple use native ID tokens where the platform has
/// them, and browser OAuth otherwise.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._config);

  final SupabaseClient _client;
  final AppConfig _config;
  bool _googleReady = false;

  GoTrueClient get _auth => _client.auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  Stream<String?> userIdChanges() async* {
    yield currentUserId;
    yield* _auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();
  }

  // ------------------------------------------------------------ phone/email

  @override
  Future<AuthOutcome> sendOtp(String phone) =>
      _invoke('auth-otp-send', {'phone': phone});

  @override
  Future<AuthOutcome> verifyOtp(String phone, String code) =>
      _invoke('auth-otp-verify', {'phone': phone, 'token': code});

  @override
  Future<AuthOutcome> signInWithPassword(String email, String password) =>
      _invoke('auth-password-sign-in', {'email': email, 'password': password});

  Future<AuthOutcome> _invoke(String fn, Map<String, String> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      return _outcome(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      log('$fn failed: $e');
      return AuthFailure(e);
    }
  }

  Future<AuthOutcome> _outcome(Map<String, dynamic> data) async {
    Duration seconds(String key) =>
        Duration(seconds: (data[key] as num?)?.toInt() ?? 0);
    switch (data['status']) {
      case 'sent':
        return OtpSent(seconds('resend_in'));
      case 'resend_too_soon':
        return ResendTooSoon(seconds('resend_in'));
      case 'invalid_code' || 'invalid_credentials':
        return WrongCredentials((data['tries_left'] as num).toInt());
      case 'locked':
        return Locked(DateTime.parse(data['locked_until'] as String));
      case 'blocked':
        return const Blocked();
      case 'send_failed':
        return const SendFailed();
      case 'signed_in':
        final session = Map<String, dynamic>.from(data['session'] as Map);
        await _auth.setSession(session['refresh_token'] as String);
        return SignedIn(isNewUser: data['is_new_user'] == true);
      default:
        return AuthFailure(data);
    }
  }

  @override
  Future<AuthOutcome> signUpWithPassword(String email, String password) async {
    try {
      final res = await _auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kIsWeb ? null : AppConfig.authCallbackUrl,
      );
      // With confirmations on, an existing email comes back with no
      // identities instead of an error (to avoid leaking accounts).
      if (res.user?.identities?.isEmpty ?? false) return const EmailInUse();
      if (res.session == null) return const ConfirmEmail();
      return const SignedIn(isNewUser: true);
    } on AuthException catch (e) {
      if (e.code == 'user_already_exists' || e.code == 'email_exists') {
        return const EmailInUse();
      }
      return AuthFailure(e);
    } catch (e) {
      return AuthFailure(e);
    }
  }

  @override
  Future<AuthOutcome> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : AppConfig.authCallbackUrl,
      );
      return const OtpSent(Duration.zero);
    } catch (e) {
      return AuthFailure(e);
    }
  }

  // ---------------------------------------------------------------- social

  bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _hasNativeGoogle =>
      !kIsWeb &&
      _config.googleWebClientId.isNotEmpty &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<AuthOutcome> signInWithGoogle() async {
    if (!_hasNativeGoogle) return _browserOAuth(OAuthProvider.google);
    try {
      final google = GoogleSignIn.instance;
      if (!_googleReady) {
        await google.initialize(
          serverClientId: _config.googleWebClientId,
          clientId: _config.googleIosClientId.isEmpty
              ? null
              : _config.googleIosClientId,
        );
        _googleReady = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return const AuthFailure('no Google ID token');
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
      return _afterSocialSignIn();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const Cancelled();
      }
      return AuthFailure(e);
    } catch (e) {
      return AuthFailure(e);
    }
  }

  @override
  Future<AuthOutcome> signInWithApple() async {
    if (!_isApplePlatform) return _browserOAuth(OAuthProvider.apple);
    try {
      final rawNonce = _nonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = credential.identityToken;
      if (idToken == null) return const AuthFailure('no Apple ID token');
      await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      // Apple shares the name only on the first sign-in and not in the
      // token, so keep it now or S-06 would have to ask again.
      final name = [
        credential.givenName,
        credential.familyName,
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
      final userId = currentUserId;
      if (name.isNotEmpty && userId != null) {
        await _client
            .from('profiles')
            .update({'full_name': name})
            .eq('id', userId)
            .isFilter('full_name', null);
      }
      return _afterSocialSignIn();
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return const Cancelled();
      return AuthFailure(e);
    } catch (e) {
      return AuthFailure(e);
    }
  }

  Future<AuthOutcome> _browserOAuth(OAuthProvider provider) async {
    try {
      final started = await _auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : AppConfig.authCallbackUrl,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      return started ? const Redirecting() : const AuthFailure('not launched');
    } catch (e) {
      return AuthFailure(e);
    }
  }

  // Social sign-in skips the Edge Functions, so check blocking here.
  Future<AuthOutcome> _afterSocialSignIn() async {
    final profile = await fetchProfile();
    if (profile?.isBlocked ?? false) {
      await signOut();
      return const Blocked();
    }
    return SignedIn(isNewUser: profile?.needsName ?? true);
  }

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  // --------------------------------------------------------------- profile

  @override
  Future<Profile?> fetchProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    final row = await _client
        .from('profiles')
        .select('id, role, full_name, email, phone, is_blocked')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : Profile.fromRow(row);
  }

  @override
  Future<void> completeProfile({
    required String fullName,
    String? email,
    required bool emailReceipts,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw StateError('Not signed in');
    final current = await _client
        .from('profiles')
        .select('notification_prefs')
        .eq('id', userId)
        .single();
    // S-06 "email me receipts" is the Orders email switch on S-08d.
    final prefs = NotificationPrefs.fromJson(current['notification_prefs'])
        .withValue(
          NotificationGroup.orders,
          NotificationChannel.email,
          emailReceipts,
        );
    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          if (email != null && email.isNotEmpty) 'email': email,
          'notification_prefs': prefs.toJson(),
        })
        .eq('id', userId);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleReady) await GoogleSignIn.instance.signOut();
  }
}

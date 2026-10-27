import '../domain/auth_outcome.dart';
import '../domain/profile.dart';

/// Every sign-in method (AUTH-01/02) and the profile it lands on. The
/// throttling rules live on the server; implementations only translate.
abstract interface class AuthRepository {
  /// Id of the signed-in user, or null for a guest.
  String? get currentUserId;

  /// Emits the user id (or null) now and on every sign-in / sign-out.
  Stream<String?> userIdChanges();

  /// Texts a 6-digit code to an E.164 number. [OtpSent], [ResendTooSoon],
  /// [Locked], [Blocked], [SendFailed] or [AuthFailure].
  Future<AuthOutcome> sendOtp(String phone);

  /// [SignedIn], [WrongCredentials], [Locked], [Blocked] or [AuthFailure].
  Future<AuthOutcome> verifyOtp(String phone, String code);

  /// [SignedIn], [WrongCredentials], [Locked], [Blocked] or [AuthFailure].
  Future<AuthOutcome> signInWithPassword(String email, String password);

  /// [SignedIn] (new user), [ConfirmEmail], [EmailInUse] or [AuthFailure].
  Future<AuthOutcome> signUpWithPassword(String email, String password);

  /// Sends the reset email. Succeeds silently for unknown emails.
  Future<AuthOutcome> resetPassword(String email);

  /// [SignedIn], [Redirecting] (web/browser), [Cancelled], [Blocked] or
  /// [AuthFailure].
  Future<AuthOutcome> signInWithGoogle();
  Future<AuthOutcome> signInWithApple();

  /// Staff invited by email set their password once (F08).
  /// [SignedIn] or [AuthFailure].
  Future<AuthOutcome> setPassword(String password);

  /// The signed-in user's profile, or null for a guest.
  Future<Profile?> fetchProfile();

  /// S-06: saves the name, optional contact email and the receipts choice.
  Future<void> completeProfile({
    required String fullName,
    String? email,
    required bool emailReceipts,
  });

  Future<void> signOut();
}

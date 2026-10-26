/// What a sign-in step ended in. Mirrors the `status` returned by the
/// auth-* Edge Functions (see supabase/functions/_shared/auth_flows.ts).
sealed class AuthOutcome {
  const AuthOutcome();
}

/// A code was texted; another can be sent after [resendIn].
class OtpSent extends AuthOutcome {
  const OtpSent(this.resendIn);
  final Duration resendIn;
}

/// Asked for a new code before the 60 s were up.
class ResendTooSoon extends AuthOutcome {
  const ResendTooSoon(this.resendIn);
  final Duration resendIn;
}

/// Wrong code (or wrong email/password) with [triesLeft] before the lock.
class WrongCredentials extends AuthOutcome {
  const WrongCredentials(this.triesLeft);
  final int triesLeft;
}

/// Too many wrong tries; this phone/email is locked until [until].
class Locked extends AuthOutcome {
  const Locked(this.until);
  final DateTime until;
}

/// The account is blocked (S-06b); no session was kept.
class Blocked extends AuthOutcome {
  const Blocked();
}

/// Signed in. [isNewUser] → complete the profile (S-06) first.
class SignedIn extends AuthOutcome {
  const SignedIn({required this.isNewUser});
  final bool isNewUser;
}

/// Email sign-up that must be confirmed from the inbox before signing in.
class ConfirmEmail extends AuthOutcome {
  const ConfirmEmail();
}

/// The email already has an account.
class EmailInUse extends AuthOutcome {
  const EmailInUse();
}

/// Browser-based OAuth started; the app resumes signed in via the redirect.
class Redirecting extends AuthOutcome {
  const Redirecting();
}

/// The person closed the Google/Apple sheet. Not an error.
class Cancelled extends AuthOutcome {
  const Cancelled();
}

/// The SMS provider refused to send.
class SendFailed extends AuthOutcome {
  const SendFailed();
}

/// Offline, server error or an unexpected provider failure.
class AuthFailure extends AuthOutcome {
  const AuthFailure([this.cause]);
  final Object? cause;
}

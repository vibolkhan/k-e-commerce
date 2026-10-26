# F05 — Sign-in & accounts

People sign in by phone, email, Google or Apple. Sign-in triggered by a protected action returns them to that action. Requirements: AUTH-01–04 and AUTH-06. App Flow: F1. Screens: S-04, S-04b, S-05, S-05b, S-05c, S-06, S-06b.

## What happens

| Step | Screen | Rule |
|---|---|---|
| Choose a method | S-04 | Phone is the default; `+855` is fixed in front. Email is the second tab. Google and Apple buttons sit under "or". |
| Send code | S-04 → S-05 | 6-digit SMS code, valid 5 minutes. A new code can be sent after 60 s (countdown, then "Resend code"). |
| Wrong code | S-05b | "That code isn't right. N tries left." |
| 5th wrong code | S-05c | The number is locked for 15 minutes. The dialog offers "Use email" or "OK"; the code boxes are disabled until the lock ends. |
| Email + password | S-04b | Same rule: "Incorrect email or password. N tries left."; the 5th wrong password locks that email for 15 minutes (the dialog offers "Use phone"). "Create an account" and "Forgot password?" are on the same tab. |
| New user | S-06 | Full name (required), optional receipts email, "Email me receipts…" switch. There is no way back; the router sends a nameless account here until it's done. |
| Blocked account | S-06b | Dialog over S-04: "This account is unavailable" with Close / Contact support. No session is kept. This is checked when a code is sent, after any sign-in, and for an existing session. |
| Done | — | The person returns to the action that asked for sign-in. If nothing asked, they go to their role's home. |

The trigger on `auth.users` creates the profile with `role = customer` (AUTH-06). Riders and staff use the same screens and the router takes them to their own home. The DB role `staff` maps to the app's `admin` shell.

### Return to intended action

```dart
if (!await requireSignIn(context, ref, AuthIntent.wishlist)) return;
await toggleWishlist(product);   // runs after sign-in, on the same page
```

`requireSignIn` (`lib/features/auth/presentation/require_sign_in.dart`) returns true straight away for signed-in users. Otherwise it pushes S-04 over the current page. That page is never removed, so its state (form input, scroll position, the cart in providers) is still there when S-04 pops back with `true`. If sign-in was opened without a page underneath (deep link, web reload), it goes to the `from` path instead; only in-app paths are accepted. Checkout, RFQ, wishlist, review and chat call this when they are built. Today it is used by "Sign in" on the placeholder customer home.

## Where the rules live

The client never decides the lockout. Phone and email sign-in go through Edge Functions, and only the service role can reach the counters.

```
supabase/
  migrations/20261027000100_auth_attempts.sql   private.auth_attempts (hashed phone/email only) +
                                                auth_attempt_status/_fail/_reset/_mark_sent (service role);
                                                handle_new_user() now also reads Google/Apple names
  functions/
    _shared/auth_flows.ts        the rules (pure, unit-tested): 5 tries, 15-min lock, 60 s resend, blocked
    _shared/supabase_deps.ts     Supabase Auth + service-role wiring
    auth-otp-send/               { phone }            → sent | resend_too_soon | locked | blocked | send_failed
    auth-otp-verify/             { phone, token }     → signed_in | invalid_code | locked | blocked
    auth-password-sign-in/       { email, password }  → signed_in | invalid_credentials | locked | blocked
  tests/database/08_auth.test.sql
lib/features/auth/
  domain/      KhPhone, Profile (role mapping), AuthOutcome, AuthIntent
  data/        AuthRepository + SupabaseAuthRepository
  presentation/ sign_in_page (S-04/b), otp_page (S-05/b/c), complete_profile_page (S-06),
               auth_dialogs (S-05c, S-06b), forgot_password_sheet, require_sign_in, auth_routes
```

Every outcome is returned as HTTP 200 with a `status` field. Only malformed requests get a 400. A `signed_in` response carries the session, which the app installs with `auth.setSession`. Limits come from `app_settings.otp`, so changing them there changes them everywhere.

Google and Apple use the native SDKs where the platform has them (Google on Android/iOS, Apple on iOS/macOS) and Supabase `signInWithIdToken`. Other platforms use browser OAuth, which returns to `kshop://login-callback` (Android intent filter and iOS URL scheme are added). Apple only gives the name on the first sign-in, so the app saves it then.

## Running it

```
npx supabase@2.120.0 start                     # stack incl. Edge Functions
flutter run -d chrome --dart-define-from-file=config/env.json
```

Locally no SMS is sent. These numbers take code **123456** (`[auth.sms.test_otp]`):

| Number | Account |
|---|---|
| 012 345 678 | Dara Sok, customer |
| 012 345 680 | Vannak Sum, **blocked** → S-06b |
| 012 000 001 | Chenda Lim, staff (super admin) → admin home |
| 012 999 999 | not registered → new account → S-06 |

Seed emails (`dara@kstore.example`, …) use the password `password123`. Any other phone number returns "We couldn't send the code" until a real SMS provider is set. To clear lockouts locally: `delete from private.auth_attempts;`.

## Tests

```
flutter analyze && flutter test                # widget + unit (162 incl. goldens)
npx supabase@2.120.0 test db                   # pgTAP incl. 08_auth
cd supabase/functions && deno test _shared/    # Edge Function rules
```

- `test/features/auth/otp_page_test.dart` covers:
  - Verify stays off until 6 digits;
  - "N tries left", including the singular;
  - the 5th wrong code shows S-05c, then the boxes are disabled with an inline lock message;
  - the right code is refused while locked;
  - "Use email" goes back to the email tab;
  - a locked number on resend;
  - the countdown, then resend;
  - a blocked account.
- `sign_in_page_test.dart` covers:
  - phone validation, sending, a locked number, a blocked number, a send failure;
  - email tries left, lockout and "Use phone", validation;
  - forgot password and create account → S-06;
  - S-06 validation;
  - blocked sessions;
  - Google and Apple;
  - **return to intended action**: page state is kept and the action runs, closing sign-in cancels, signed-in users go straight through.
- `auth_rules_test.dart` covers:
  - phone rules, role mapping, safe return paths, redirects;
  - the full app with a rider, a blocked session and a guest.
- CI gets a new `edge-functions` job (`deno fmt`, `check`, `test`).

The repository was also run against the local stack, outside the committed tests:

- OTP right and wrong codes;
- a new user saving S-06 through RLS;
- blocked users on phone and password;
- staff → admin.

## Setup the project owner must do

1. **SMS provider** (PRD assumption). Configure it in the hosted project's Auth settings. Locally a placeholder Twilio entry exists only so the test numbers work. Set SMS OTP expiry to 300 s and the "SMS sent" rate limit to suit.
2. **Google:**
   - Create OAuth clients for web, iOS and Android.
   - Hosted Auth: client IDs (web first), secret.
   - App: `GOOGLE_WEB_CLIENT_ID` and `GOOGLE_IOS_CLIENT_ID` in `config/<env>.json`.
   - iOS: add the reversed iOS client ID as a URL scheme.
   - Android: register the SHA-1 of each signing key.
3. **Apple:**
   - Enable the "Sign in with Apple" capability for the iOS bundle id.
   - Create a Services ID and key for web/Android.
   - Hosted Auth: client IDs (bundle id, Services ID), secret.
4. **Redirect URLs** in hosted Auth: `kshop://login-callback` and the web origin(s).
5. Locally, both social providers are off in `supabase/config.toml` (env-driven) until those IDs exist.

## Decisions and assumptions

- The lockout is enforced on the server (Edge Functions plus a private table), not in the app. The email lockout reuses the same 5 tries / 15 minutes so the S-04b "N tries left" text is true.
- A blocked account is checked before a code is sent, matching the design where S-06b sits over S-04. That tells someone with that number it's blocked, which is the point of the screen. Email/password says "blocked" only after the right password.
- New user = profile with no name. Google usually provides a name, so S-06 is skipped; Apple provides one only the first time.
- **Design deviation:** the Google and Apple buttons keep the S-04 outline style but add each provider's official logo, as their branding rules require.
- "Terms" and "Privacy Policy" are emphasised but not linked yet; the pages come with the CMS content pages.
- "Contact support" shows a short notice until support chat exists (`contactSupportProvider` is the hook).
- The F04 `profiles.email` column is used as the receipts email from S-06. The auth email is not changed.

## Follow-ups

- Native Khmer review of the new `auth*` strings (drafted for this task).
- Linking Google/Apple to a phone account only after OTP confirmation (App Flow F1 edge case). For now Supabase's default identity linking applies.
- Contact support, and the Terms/Privacy links, once chat and content pages exist.
- F06 owns the full role guards and the Account area (profile editing, sign out). F05 adds a temporary Sign in / Sign out on the placeholder home.
- Windows desktop builds need Developer Mode for plugin symlinks (`flutter pub get` warns). Tests and web are unaffected.

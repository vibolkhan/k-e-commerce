// Sign-in flows behind the auth-* Edge Functions (F05, AUTH-01).
//
// Pure logic: every side effect goes through `AuthDeps`, so the rules
// (5 tries, 15-minute lock, 60 s resend, blocked accounts) are unit-tested
// without a running Supabase. index.ts files wire the real dependencies.
//
// Every outcome is HTTP 200 with a `status`; only malformed requests are 400.

import { normalizeEmail, normalizeKhPhone } from "./phone.ts";

export type AttemptKind = "otp" | "password";

export interface AttemptState {
  locked_until: string | null;
  tries_left: number;
  resend_in: number;
}

export interface AttemptStore {
  status(kind: AttemptKind, id: string): Promise<AttemptState>;
  fail(kind: AttemptKind, id: string): Promise<AttemptState>;
  reset(kind: AttemptKind, id: string): Promise<void>;
  markSent(kind: AttemptKind, id: string): Promise<void>;
}

export interface AuthSession {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  user_id: string;
}

export interface AuthGateway {
  /**
   * Sends an SMS code. Resolves null on success, or Auth's error code when it
   * refuses (e.g. `phone_provider_disabled`, `sms_send_failed`).
   */
  sendOtp(phone: string): Promise<string | null>;
  /** The session for a right code, null for a wrong or expired one. */
  verifyOtp(phone: string, token: string): Promise<AuthSession | null>;
  /** The session for a right password, null otherwise. */
  signInWithPassword(email: string, password: string): Promise<AuthSession | null>;
  /** Revokes a session that must not be used (blocked account). */
  signOut(accessToken: string): Promise<void>;
}

export interface ProfileLookup {
  /** Blocked flag and name for a user id, null when there is no profile yet. */
  byId(userId: string): Promise<{ is_blocked: boolean; full_name: string | null } | null>;
  /** True when a blocked profile owns this phone. */
  isPhoneBlocked(phone: string): Promise<boolean>;
}

export interface AuthDeps {
  attempts: AttemptStore;
  auth: AuthGateway;
  profiles: ProfileLookup;
}

export type FlowResult =
  | { status: "sent"; resend_in: number }
  | { status: "resend_too_soon"; resend_in: number }
  | { status: "locked"; locked_until: string }
  | { status: "invalid_code"; tries_left: number }
  | { status: "invalid_credentials"; tries_left: number }
  | { status: "blocked" }
  | { status: "signed_in"; session: AuthSession; is_new_user: boolean }
  | { status: "send_failed"; reason: string };

export class BadRequest extends Error {}

function requireString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== "string" || value.trim() === "") {
    throw new BadRequest(`${key} is required`);
  }
  return value;
}

function lockedResult(state: AttemptState): FlowResult | null {
  return state.locked_until ? { status: "locked", locked_until: state.locked_until } : null;
}

// After a right code/password: clear failures, stop blocked accounts,
// and tell the app whether S-06 (complete profile) is needed.
async function finishSignIn(
  deps: AuthDeps,
  kind: AttemptKind,
  id: string,
  session: AuthSession,
): Promise<FlowResult> {
  await deps.attempts.reset(kind, id);
  const profile = await deps.profiles.byId(session.user_id);
  if (profile?.is_blocked) {
    await deps.auth.signOut(session.access_token);
    return { status: "blocked" };
  }
  return { status: "signed_in", session, is_new_user: !profile?.full_name };
}

export async function sendOtp(deps: AuthDeps, body: Record<string, unknown>): Promise<FlowResult> {
  const phone = normalizeKhPhone(requireString(body, "phone"));
  if (!phone) throw new BadRequest("phone is not a Cambodian mobile number");

  const state = await deps.attempts.status("otp", phone);
  const locked = lockedResult(state);
  if (locked) return locked;
  if (state.resend_in > 0) return { status: "resend_too_soon", resend_in: state.resend_in };
  if (await deps.profiles.isPhoneBlocked(phone)) return { status: "blocked" };

  const refused = await deps.auth.sendOtp(phone);
  if (refused) return { status: "send_failed", reason: refused };
  await deps.attempts.markSent("otp", phone);
  return { status: "sent", resend_in: (await deps.attempts.status("otp", phone)).resend_in };
}

export async function verifyOtp(
  deps: AuthDeps,
  body: Record<string, unknown>,
): Promise<FlowResult> {
  const phone = normalizeKhPhone(requireString(body, "phone"));
  if (!phone) throw new BadRequest("phone is not a Cambodian mobile number");
  const token = requireString(body, "token").trim();
  if (!/^\d{6}$/.test(token)) throw new BadRequest("token must be 6 digits");

  const locked = lockedResult(await deps.attempts.status("otp", phone));
  if (locked) return locked;

  const session = await deps.auth.verifyOtp(phone, token);
  if (!session) {
    const after = await deps.attempts.fail("otp", phone);
    return lockedResult(after) ?? { status: "invalid_code", tries_left: after.tries_left };
  }
  return finishSignIn(deps, "otp", phone, session);
}

export async function passwordSignIn(
  deps: AuthDeps,
  body: Record<string, unknown>,
): Promise<FlowResult> {
  const email = normalizeEmail(requireString(body, "email"));
  if (!email) throw new BadRequest("email is not valid");
  const password = requireString(body, "password");

  const locked = lockedResult(await deps.attempts.status("password", email));
  if (locked) return locked;

  const session = await deps.auth.signInWithPassword(email, password);
  if (!session) {
    const after = await deps.attempts.fail("password", email);
    return lockedResult(after) ?? { status: "invalid_credentials", tries_left: after.tries_left };
  }
  return finishSignIn(deps, "password", email, session);
}

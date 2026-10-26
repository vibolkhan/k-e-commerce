// Real dependencies for the auth-* functions: Supabase Auth through the
// anon key (as the user would), counters and profiles through the service role.

import { createClient, type Session } from "@supabase/supabase-js";
import type { AttemptKind, AttemptState, AuthDeps, AuthSession } from "./auth_flows.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function toSession(session: Session | null): AuthSession | null {
  if (!session?.user) return null;
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in,
    user_id: session.user.id,
  };
}

export function supabaseDeps(): AuthDeps {
  const url = env("SUPABASE_URL");
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const service = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), options);
  // A fresh anon client per call so sessions never leak between requests.
  const anon = () => createClient(url, env("SUPABASE_ANON_KEY"), options);

  async function rpc(name: string, kind: AttemptKind, id: string) {
    const { data, error } = await service.rpc(name, { p_kind: kind, p_identifier: id });
    if (error) throw error;
    return data;
  }

  return {
    attempts: {
      status: (kind, id) => rpc("auth_attempt_status", kind, id) as Promise<AttemptState>,
      fail: (kind, id) => rpc("auth_attempt_fail", kind, id) as Promise<AttemptState>,
      reset: async (kind, id) => void (await rpc("auth_attempt_reset", kind, id)),
      markSent: async (kind, id) => void (await rpc("auth_attempt_mark_sent", kind, id)),
    },
    auth: {
      async sendOtp(phone) {
        const { error } = await anon().auth.signInWithOtp({ phone });
        if (!error) return null;
        console.error("signInWithOtp", error.status, error.code, error.message);
        return error.code ?? `http_${error.status ?? "unknown"}`;
      },
      async verifyOtp(phone, token) {
        const { data, error } = await anon().auth.verifyOtp({ phone, token, type: "sms" });
        return error ? null : toSession(data.session);
      },
      async signInWithPassword(email, password) {
        const { data, error } = await anon().auth.signInWithPassword({ email, password });
        return error ? null : toSession(data.session);
      },
      async signOut(accessToken) {
        await service.auth.admin.signOut(accessToken, "global");
      },
    },
    profiles: {
      async byId(userId) {
        const { data, error } = await service
          .from("profiles")
          .select("is_blocked, full_name")
          .eq("id", userId)
          .maybeSingle();
        if (error) throw error;
        return data;
      },
      async isPhoneBlocked(phone) {
        const { count, error } = await service
          .from("profiles")
          .select("id", { count: "exact", head: true })
          .eq("phone", phone)
          .eq("is_blocked", true);
        if (error) throw error;
        return (count ?? 0) > 0;
      },
    },
  };
}

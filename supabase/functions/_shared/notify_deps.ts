// Real dependencies for notify: the database through the service role, and
// FCM when its secrets are set.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { fcmSender, noopSender } from "./fcm.ts";
import type { DeviceToken, NewNotification, NotifyHttpDeps, Profile } from "./notify_flows.ts";
import type { Locale, Role } from "./notify_types.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function pushSender() {
  const projectId = Deno.env.get("FCM_PROJECT_ID");
  const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FCM_PRIVATE_KEY");
  if (!projectId || !clientEmail || !privateKey) return noopSender;
  return fcmSender(
    { projectId, clientEmail, privateKey },
    { webBaseUrl: Deno.env.get("APP_WEB_URL") },
  );
}

/** Created once per worker, so the FCM access token is reused between calls. */
let push: ReturnType<typeof pushSender> | null = null;

/** For other Edge Functions that import `notify` with their own client. */
export function notifyDeps(service: SupabaseClient = serviceClient()) {
  push ??= pushSender();
  return {
    push,
    async recipients(ids: string[]): Promise<Profile[]> {
      const { data, error } = await service
        .from("profiles")
        .select("id, role, locale, notification_prefs")
        .in("id", ids)
        .is("deleted_at", null)
        .eq("is_blocked", false);
      if (error) throw error;
      return (data ?? []).map((row) => ({
        id: row.id as string,
        role: row.role as Role,
        locale: (row.locale === "km" ? "km" : "en") as Locale,
        prefs: (row.notification_prefs ?? {}) as Profile["prefs"],
      }));
    },
    async insertNotifications(rows: NewNotification[]): Promise<string[]> {
      const { data, error } = await service
        .from("notifications")
        .insert(rows)
        .select("id, profile_id");
      if (error) throw error;
      // One row per recipient, so the profile id maps back to its row.
      const ids = new Map((data ?? []).map((row) => [row.profile_id as string, row.id as string]));
      return rows.map((row) => ids.get(row.profile_id)!);
    },
    async unreadCounts(ids: string[]): Promise<Map<string, number>> {
      const { data, error } = await service
        .from("notifications")
        .select("profile_id")
        .in("profile_id", ids)
        .is("read_at", null);
      if (error) throw error;
      const counts = new Map<string, number>();
      for (const row of data ?? []) {
        const id = row.profile_id as string;
        counts.set(id, (counts.get(id) ?? 0) + 1);
      }
      return counts;
    },
    async tokens(ids: string[]): Promise<DeviceToken[]> {
      const { data, error } = await service
        .from("device_tokens")
        .select("profile_id, token, platform")
        .in("profile_id", ids);
      if (error) throw error;
      return (data ?? []) as DeviceToken[];
    },
    async deleteTokens(tokens: string[]): Promise<void> {
      const { error } = await service.from("device_tokens").delete().in("token", tokens);
      if (error) throw error;
    },
  };
}

export function notifyHttpDeps(): NotifyHttpDeps {
  const service = serviceClient();
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  return {
    ...notifyDeps(service),
    async callerFor(authorization) {
      const token = authorization?.replace(/^Bearer\s+/i, "").trim();
      if (!token) return null;
      if (token === serviceKey) return { kind: "service" };
      const { data, error } = await service.auth.getUser(token);
      const id = error ? null : data.user?.id;
      return id ? { kind: "user", id } : null;
    },
    selfTestEnabled: Deno.env.get("NOTIFY_SELF_TEST") === "true",
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  };
}

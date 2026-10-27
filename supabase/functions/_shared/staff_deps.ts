// Real dependencies for staff-manage: everything through the service role.

import { createClient } from "@supabase/supabase-js";
import { smsSenderFor } from "./sms.ts";
import type { Account, Contact, StaffDeps, StaffMember } from "./staff_flows.ts";

/** Long enough to mean "until re-invited". */
const REMOVED_BAN = "876000h";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

export function staffDeps(): StaffDeps {
  const url = env("SUPABASE_URL");
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const service = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), options);
  const appUrl = (Deno.env.get("APP_WEB_URL") || "http://127.0.0.1:3000").replace(/\/$/, "");
  // Email invitees land on the set-password step (S-04b afterwards).
  const emailRedirect = `${appUrl}/sign-in/set-password`;

  const sms = smsSenderFor((name) => Deno.env.get(name), async (phone, body) => {
    const { error } = await service.rpc("dev_record_sms", { p_phone: phone, p_body: body });
    if (error) throw error;
  });

  return {
    appUrl,
    now: () => new Date(),
    async userIdFor(authorization) {
      const token = authorization?.replace(/^Bearer\s+/i, "").trim();
      if (!token) return null;
      const { data, error } = await service.auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    async member(profileId) {
      const { data, error } = await service.rpc("staff_member_info", { p_uid: profileId })
        .maybeSingle();
      if (error) throw error;
      return (data as StaffMember | null) ?? null;
    },
    async accountFor(contact: Contact) {
      const { data, error } = await service.rpc(
        "staff_account_for",
        contact.kind === "email" ? { p_email: contact.email } : { p_phone: contact.phone },
      ).maybeSingle();
      if (error) throw error;
      return (data as Account | null) ?? null;
    },
    async activeSuperAdmins() {
      const { count, error } = await service
        .from("staff_members")
        .select("profile_id", { count: "exact", head: true })
        .eq("staff_role", "super_admin")
        .eq("status", "active");
      if (error) throw error;
      return count ?? 0;
    },
    async createUser(contact, fullName) {
      const metadata = { full_name: fullName, needs_password: contact.kind === "email" };
      const { data, error } = await service.auth.admin.createUser(
        contact.kind === "email"
          ? { email: contact.email, user_metadata: metadata }
          : { phone: contact.phone, phone_confirm: true, user_metadata: metadata },
      );
      if (error) throw error;
      return data.user.id;
    },
    async sendEmailInvite(email, isNewUser) {
      const { error } = await service.auth.admin.inviteUserByEmail(email, {
        redirectTo: emailRedirect,
      });
      if (!error) return;
      // Auth only invites unconfirmed users; anyone who has signed in before
      // (a re-invited member) gets a sign-in link instead.
      if (isNewUser) throw error;
      const { error: linkError } = await service.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false, emailRedirectTo: emailRedirect },
      });
      if (linkError) throw linkError;
    },
    sendSms: (phone, body) => sms.send(phone, body),
    async saveInvite({ profileId, fullName, role, invitedBy, invitedAt, expiresAt }) {
      const { error: profileError } = await service
        .from("profiles")
        .update({ role: "staff", full_name: fullName })
        .eq("id", profileId);
      if (profileError) throw profileError;
      const { error } = await service.from("staff_members").upsert({
        profile_id: profileId,
        staff_role: role,
        status: "invited",
        invited_by: invitedBy,
        invited_at: invitedAt.toISOString(),
        invite_expires_at: expiresAt.toISOString(),
      });
      if (error) throw error;
      const { error: banError } = await service.auth.admin.updateUserById(profileId, {
        ban_duration: "none",
      });
      if (banError) throw banError;
    },
    async setRole(profileId, role) {
      const { error } = await service
        .from("staff_members")
        .update({ staff_role: role })
        .eq("profile_id", profileId);
      if (error) throw error;
    },
    async remove(profileId) {
      const { error } = await service
        .from("staff_members")
        .update({ status: "removed" })
        .eq("profile_id", profileId);
      if (error) throw error;
      // Banning also stops their refresh tokens, so open sessions end.
      const { error: banError } = await service.auth.admin.updateUserById(profileId, {
        ban_duration: REMOVED_BAN,
      });
      if (banError) throw banError;
    },
  };
}

// Staff management behind the staff-manage Edge Function (F08, ADM-09).
//
// Pure logic: every side effect goes through `StaffDeps`, so the rules are
// unit-tested without a running Supabase. The database backs them up:
// staff_members is writable only by the service role, and a trigger keeps an
// active super admin (migrations/20261031000100_staff_admin.sql).
//
// Body: { action: "invite" | "resend" | "update_role" | "remove", ... }.
// Every outcome is HTTP 200 with a `status`; a malformed body is 400 and a
// missing or invalid session is 401.

import { BadRequest, Unauthorized } from "./errors.ts";
import { normalizeEmail, normalizeKhPhone } from "./phone.ts";

export const STAFF_ROLES = ["super_admin", "sales", "support", "catalog"] as const;
export type StaffRole = typeof STAFF_ROLES[number];
export type StaffStatus = "active" | "invited" | "removed";

/** A-14e: "The invite expires in 7 days." */
export const INVITE_DAYS = 7;
const MAX_NAME_LENGTH = 100;

const ROLE_LABELS: Record<StaffRole, string> = {
  super_admin: "Super admin",
  sales: "Sales",
  support: "Support",
  catalog: "Catalog",
};

export type Contact = { kind: "email"; email: string } | { kind: "phone"; phone: string };

export interface StaffMember {
  profile_id: string;
  full_name: string | null;
  /** The sign-in email (auth), if any. */
  email: string | null;
  /** The sign-in phone (E.164), if any. */
  phone: string | null;
  staff_role: StaffRole;
  status: StaffStatus;
}

/** An existing account found by email or phone. */
export interface Account {
  profile_id: string;
  /** profiles.role: customer | business | rider | staff. */
  role: string;
  staff_status: StaffStatus | null;
}

export interface StaffDeps {
  /** The caller's user id from their `Authorization` header, null if not valid. */
  userIdFor(authorization: string | null): Promise<string | null>;
  member(profileId: string): Promise<StaffMember | null>;
  accountFor(contact: Contact): Promise<Account | null>;
  activeSuperAdmins(): Promise<number>;
  /** Creates the auth user for a new invitee and returns their id. */
  createUser(contact: Contact, fullName: string): Promise<string>;
  /** Sends the sign-in link by email (Auth invite or magic link). */
  sendEmailInvite(email: string, isNewUser: boolean): Promise<void>;
  sendSms(phone: string, body: string): Promise<void>;
  /** profiles.role = staff + name; staff_members row as invited; unbans. */
  saveInvite(invite: {
    profileId: string;
    fullName: string;
    role: StaffRole;
    invitedBy: string;
    invitedAt: Date;
    expiresAt: Date;
  }): Promise<void>;
  setRole(profileId: string, role: StaffRole): Promise<void>;
  /** status = removed, and the account can no longer sign in. */
  remove(profileId: string): Promise<void>;
  now(): Date;
  /** The web app, linked from invite SMS. */
  appUrl: string;
}

export type StaffResult =
  | { status: "invited"; profile_id: string; expires_at: string }
  | { status: "resent"; expires_at: string }
  | { status: "updated" }
  | { status: "removed" }
  | { status: "forbidden" }
  | { status: "invalid"; field: "full_name" | "contact" | "role" }
  | { status: "account_exists" }
  | { status: "already_staff" }
  | { status: "not_found" }
  | { status: "not_invited" }
  | { status: "self" }
  | { status: "last_super_admin" }
  | { status: "send_failed" };

function text(body: Record<string, unknown>, key: string): string | null {
  const value = body[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new BadRequest(`${key} must be a string`);
  return value.trim();
}

function requiredId(body: Record<string, unknown>): string {
  const id = text(body, "profile_id");
  if (!id) throw new BadRequest("profile_id is required");
  return id;
}

function roleOf(value: string | null): StaffRole | null {
  return STAFF_ROLES.includes(value as StaffRole) ? value as StaffRole : null;
}

/** Email if it has an @, otherwise a Cambodian phone number. */
export function parseContact(input: string): Contact | null {
  if (input.includes("@")) {
    const email = normalizeEmail(input);
    return email ? { kind: "email", email } : null;
  }
  const phone = normalizeKhPhone(input);
  return phone ? { kind: "phone", phone } : null;
}

/** "28 Oct 2026" in Phnom Penh (UTC+7, no DST). */
export function formatInviteDate(date: Date): string {
  const local = new Date(date.getTime() + 7 * 3600 * 1000);
  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  return `${local.getUTCDate()} ${months[local.getUTCMonth()]} ${local.getUTCFullYear()}`;
}

export function inviteSms(
  { inviter, role, appUrl, expiresAt }: {
    inviter: string;
    role: StaffRole;
    appUrl: string;
    expiresAt: Date;
  },
): string {
  return `K Admin: ${inviter} invited you to the K back-office as ${ROLE_LABELS[role]}. ` +
    `Open ${appUrl.replace(/\/$/, "")}/sign-in and sign in with this number. ` +
    `The invite expires on ${formatInviteDate(expiresAt)}.`;
}

/** The whole staff-manage function. */
export async function manageStaff(
  deps: StaffDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<StaffResult> {
  const callerId = await deps.userIdFor(req.headers.get("Authorization"));
  if (!callerId) throw new Unauthorized();
  const caller = await deps.member(callerId);
  if (!caller || caller.status !== "active" || caller.staff_role !== "super_admin") {
    return { status: "forbidden" };
  }

  switch (text(body, "action")) {
    case "invite":
      return await invite(deps, caller, body);
    case "resend":
      return await resend(deps, caller, requiredId(body));
    case "update_role":
      return await updateRole(deps, callerId, requiredId(body), roleOf(text(body, "role")));
    case "remove":
      return await remove(deps, callerId, requiredId(body));
    default:
      throw new BadRequest("action must be invite, resend, update_role or remove");
  }
}

async function deliver(
  deps: StaffDeps,
  caller: StaffMember,
  contact: Contact,
  role: StaffRole,
  expiresAt: Date,
  isNewUser: boolean,
): Promise<boolean> {
  try {
    if (contact.kind === "email") await deps.sendEmailInvite(contact.email, isNewUser);
    else {
      await deps.sendSms(
        contact.phone,
        inviteSms({ inviter: caller.full_name ?? "K", role, appUrl: deps.appUrl, expiresAt }),
      );
    }
    return true;
  } catch (e) {
    console.error("staff invite delivery", e);
    return false;
  }
}

function expiryFrom(now: Date): Date {
  return new Date(now.getTime() + INVITE_DAYS * 24 * 3600 * 1000);
}

async function invite(
  deps: StaffDeps,
  caller: StaffMember,
  body: Record<string, unknown>,
): Promise<StaffResult> {
  const fullName = text(body, "full_name") ?? "";
  if (fullName === "" || fullName.length > MAX_NAME_LENGTH) {
    return { status: "invalid", field: "full_name" };
  }
  const contact = parseContact(text(body, "contact") ?? "");
  if (!contact) return { status: "invalid", field: "contact" };
  const role = roleOf(text(body, "role"));
  if (!role) return { status: "invalid", field: "role" };

  const existing = await deps.accountFor(contact);
  if (existing && existing.role !== "staff") return { status: "account_exists" };
  if (existing && existing.staff_status !== "removed") return { status: "already_staff" };

  const profileId = existing?.profile_id ?? await deps.createUser(contact, fullName);
  const now = deps.now();
  const expiresAt = expiryFrom(now);
  await deps.saveInvite({
    profileId,
    fullName,
    role,
    invitedBy: caller.profile_id,
    invitedAt: now,
    expiresAt,
  });
  if (!await deliver(deps, caller, contact, role, expiresAt, !existing)) {
    return { status: "send_failed" };
  }
  return { status: "invited", profile_id: profileId, expires_at: expiresAt.toISOString() };
}

async function resend(
  deps: StaffDeps,
  caller: StaffMember,
  profileId: string,
): Promise<StaffResult> {
  const member = await deps.member(profileId);
  if (!member || member.status === "removed") return { status: "not_found" };
  if (member.status !== "invited") return { status: "not_invited" };
  const contact: Contact | null = member.email
    ? { kind: "email", email: member.email }
    : member.phone
    ? { kind: "phone", phone: member.phone }
    : null;
  if (!contact) return { status: "send_failed" };

  const now = deps.now();
  const expiresAt = expiryFrom(now);
  await deps.saveInvite({
    profileId,
    fullName: member.full_name ?? "",
    role: member.staff_role,
    invitedBy: caller.profile_id,
    invitedAt: now,
    expiresAt,
  });
  if (!await deliver(deps, caller, contact, member.staff_role, expiresAt, false)) {
    return { status: "send_failed" };
  }
  return { status: "resent", expires_at: expiresAt.toISOString() };
}

/** Self-edits and leaving no active super admin are refused. */
async function guardChange(
  deps: StaffDeps,
  callerId: string,
  member: StaffMember | null,
  keepsSuperAdmin: boolean,
): Promise<StaffResult | null> {
  if (!member || member.status === "removed") return { status: "not_found" };
  if (member.profile_id === callerId) return { status: "self" };
  const losesSuperAdmin = member.staff_role === "super_admin" && member.status === "active" &&
    !keepsSuperAdmin;
  if (losesSuperAdmin && await deps.activeSuperAdmins() <= 1) {
    return { status: "last_super_admin" };
  }
  return null;
}

async function updateRole(
  deps: StaffDeps,
  callerId: string,
  profileId: string,
  role: StaffRole | null,
): Promise<StaffResult> {
  if (!role) return { status: "invalid", field: "role" };
  const member = await deps.member(profileId);
  const refused = await guardChange(deps, callerId, member, role === "super_admin");
  if (refused) return refused;
  if (member!.staff_role !== role) await deps.setRole(profileId, role);
  return { status: "updated" };
}

async function remove(deps: StaffDeps, callerId: string, profileId: string): Promise<StaffResult> {
  const member = await deps.member(profileId);
  const refused = await guardChange(deps, callerId, member, false);
  if (refused) return refused;
  await deps.remove(profileId);
  return { status: "removed" };
}

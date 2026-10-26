// Account deletion behind the account-delete Edge Function (F06, AUTH-07).
//
// Pure logic: every side effect goes through `AccountDeps`, so the rules are
// unit-tested without a running Supabase. Deleting the auth user fires the
// database trigger that anonymises the profile and keeps invoice records
// (see migrations/20261028000100_account_deletion.sql).
//
// Every outcome is HTTP 200 with a `status`; a malformed body is 400 and a
// missing or invalid session is 401.

import { BadRequest, Unauthorized } from "./errors.ts";

/** Only shoppers delete themselves; an admin removes rider and staff accounts. */
const SELF_SERVICE_ROLES = new Set(["customer", "business"]);

const MAX_REASON_LENGTH = 500;

export interface DeletionCheck {
  role: string | null;
  active_orders: number;
  open_returns: number;
}

export interface AccountDeps {
  /** The caller's user id from their `Authorization` header, null if not valid. */
  userIdFor(authorization: string | null): Promise<string | null>;
  /** Role and unfinished orders/returns (public.account_deletion_check). */
  deletionCheck(userId: string): Promise<DeletionCheck>;
  /** Removes the user's private Storage files (licence, chat attachments). */
  removeFiles(userId: string): Promise<void>;
  /** Deletes the auth user; the trigger anonymises the profile with [reason]. */
  deleteUser(userId: string, reason: string | null): Promise<void>;
}

export type DeleteAccountResult =
  | { status: "deleted" }
  | { status: "has_active_orders"; active_orders: number; open_returns: number }
  | { status: "not_allowed" };

function optionalReason(body: Record<string, unknown>): string | null {
  const value = body.reason;
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw new BadRequest("reason must be a string");
  const trimmed = value.trim().slice(0, MAX_REASON_LENGTH);
  return trimmed === "" ? null : trimmed;
}

/** `{ reason? }` with the caller's session → deleted | has_active_orders | not_allowed. */
export async function deleteAccount(
  deps: AccountDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<DeleteAccountResult> {
  const userId = await deps.userIdFor(req.headers.get("Authorization"));
  if (!userId) throw new Unauthorized();
  const reason = optionalReason(body);

  const check = await deps.deletionCheck(userId);
  if (!check.role || !SELF_SERVICE_ROLES.has(check.role)) return { status: "not_allowed" };
  if (check.active_orders > 0 || check.open_returns > 0) {
    return {
      status: "has_active_orders",
      active_orders: check.active_orders,
      open_returns: check.open_returns,
    };
  }

  await deps.removeFiles(userId);
  await deps.deleteUser(userId, reason);
  return { status: "deleted" };
}

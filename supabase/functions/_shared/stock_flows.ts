// Stock behind the inventory-manage Edge Function and the order flows (F10,
// ADM-03, CAT-05, CHK-04; A-06, A-06a).
//
// Pure logic: every side effect goes through `StockDeps` / `OrderStockDeps`.
// The numbers are decided in the database (migrations/20261102000100_inventory.sql):
// reserve_stock, release_stock and commit_stock lock the stock rows, and
// adjust_stock acts as the staff member so audit_logs records who changed it.
//
// inventory-manage body: { action: "adjust", variant_id, mode, qty, reason,
// note?, low_stock_at? }. Every outcome is HTTP 200 with a `status`; a
// malformed body is 400 and a missing or invalid session is 401.
//
// Checkout, payment, cancel and fulfilment (F17 – F20) import reserveForOrder,
// releaseForOrder and commitForOrder. Each one tells catalog staff when a
// variant falls to its low-stock level; a failed alert never fails the order.

import { BadRequest } from "./errors.ts";
import { type CatalogDeps, requireEditor } from "./catalog_flows.ts";
import { notify, type NotifyDeps } from "./notify_flows.ts";

export const ADJUST_MODES = ["add", "remove", "set"] as const;
export type AdjustMode = typeof ADJUST_MODES[number];

/** Which stock_reason each mode may record (A-06a reason menu). */
export const REASONS_BY_MODE: Record<AdjustMode, readonly string[]> = {
  add: ["received", "returned", "adjustment"],
  remove: ["damaged", "adjustment"],
  set: ["adjustment"],
};

export const STOCK_LIMITS = { maxQty: 100_000, note: 500 } as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface AdjustInput {
  variant_id: string;
  mode: AdjustMode;
  qty: number;
  reason: string;
  note?: string;
  low_stock_at?: number;
}

/** A variant that just fell to its alert level (private.low_stock_crossings). */
export interface LowStock {
  variant_id: string;
  sku: string;
  product_name: string;
  available: number;
  threshold: number;
}

/** What alerts need: notify plumbing and who gets told. */
export interface AlertDeps {
  notify: NotifyDeps;
  /** Active catalog staff and super admins (low_stock_recipients). */
  lowStockRecipients(): Promise<string[]>;
}

export interface StockDeps extends Pick<CatalogDeps, "userIdFor" | "member">, AlertDeps {
  /** adjust_stock: adjusted | below_reserved | not_found | invalid. */
  adjustStock(actorId: string, input: AdjustInput): Promise<Record<string, unknown>>;
}

export interface FieldError {
  field: string;
  code: "required" | "invalid" | "too_long";
}

export type AdjustResult =
  | {
    status: "adjusted";
    on_hand: number;
    reserved: number;
    available: number;
    low_stock_at: number;
    delta: number;
  }
  | { status: "below_reserved"; reserved: number }
  | { status: "invalid"; errors: FieldError[] }
  | { status: "not_found" }
  | { status: "forbidden" };

/** The whole inventory-manage function. */
export async function manageInventory(
  deps: StockDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<AdjustResult> {
  const callerId = await requireEditor(deps, req);
  if (!callerId) return { status: "forbidden" };
  if (body.action !== "adjust") throw new BadRequest("action must be adjust");

  const checked = checkAdjust(body);
  if ("errors" in checked) return { status: "invalid", errors: checked.errors };

  const result = await deps.adjustStock(callerId, checked);
  switch (result.status) {
    case "adjusted":
      await alertLowStock(deps, result.low as LowStock[] | undefined);
      return {
        status: "adjusted",
        on_hand: Number(result.on_hand),
        reserved: Number(result.reserved),
        available: Number(result.available),
        low_stock_at: Number(result.low_stock_at),
        delta: Number(result.delta),
      };
    case "below_reserved":
      return { status: "below_reserved", reserved: Number(result.reserved) };
    case "not_found":
      return { status: "not_found" };
    case "invalid":
      return { status: "invalid", errors: [{ field: String(result.field), code: "invalid" }] };
    default:
      throw new Error(`adjust_stock returned ${JSON.stringify(result)}`);
  }
}

/** Cleans an adjust body, or lists what is wrong with it. */
export function checkAdjust(body: Record<string, unknown>): AdjustInput | { errors: FieldError[] } {
  const errors: FieldError[] = [];
  const { variant_id, mode, qty, reason, note, low_stock_at } = body;

  if (typeof variant_id !== "string" || !UUID_PATTERN.test(variant_id)) {
    errors.push({ field: "variant_id", code: variant_id == null ? "required" : "invalid" });
  }
  const validMode = (ADJUST_MODES as readonly unknown[]).includes(mode);
  if (!validMode) errors.push({ field: "mode", code: mode == null ? "required" : "invalid" });

  const min = mode === "set" ? 0 : 1;
  if (typeof qty !== "number" || !Number.isInteger(qty) || qty < min || qty > STOCK_LIMITS.maxQty) {
    errors.push({ field: "qty", code: qty == null ? "required" : "invalid" });
  }
  if (typeof reason !== "string" || reason === "") {
    errors.push({ field: "reason", code: "required" });
  } else if (validMode && !REASONS_BY_MODE[mode as AdjustMode].includes(reason)) {
    errors.push({ field: "reason", code: "invalid" });
  }
  if (note != null && typeof note !== "string") errors.push({ field: "note", code: "invalid" });
  const cleanNote = typeof note === "string" ? note.trim() : "";
  if (cleanNote.length > STOCK_LIMITS.note) errors.push({ field: "note", code: "too_long" });
  if (
    low_stock_at != null &&
    (typeof low_stock_at !== "number" || !Number.isInteger(low_stock_at) || low_stock_at < 0 ||
      low_stock_at > STOCK_LIMITS.maxQty)
  ) {
    errors.push({ field: "low_stock_at", code: "invalid" });
  }

  if (errors.length > 0) return { errors };
  return {
    variant_id: variant_id as string,
    mode: mode as AdjustMode,
    qty: qty as number,
    reason: reason as string,
    ...(cleanNote ? { note: cleanNote } : {}),
    ...(low_stock_at != null ? { low_stock_at: low_stock_at as number } : {}),
  };
}

/** Tells catalog staff about each variant that fell to its alert level. */
export async function alertLowStock(deps: AlertDeps, low: LowStock[] | undefined): Promise<number> {
  if (!low || low.length === 0) return 0;
  try {
    const staff = await deps.lowStockRecipients();
    if (staff.length === 0) return 0;
    for (const item of low) {
      await notify(deps.notify, staff, "admin_low_stock", {
        product_name: item.product_name,
        stock: item.available,
        threshold: item.threshold,
      });
    }
    return low.length;
  } catch (e) {
    // The stock change already happened; a missed alert must not undo it.
    console.error("low-stock alert failed", e);
    return 0;
  }
}

// ---------------------------------------------------------------- order stock

export interface OrderStockDeps extends AlertDeps {
  reserveStock(orderId: string): Promise<Record<string, unknown>>;
  releaseStock(orderId: string): Promise<Record<string, unknown>>;
  commitStock(orderId: string): Promise<Record<string, unknown>>;
}

export type ReserveResult =
  | { status: "reserved" }
  | {
    status: "insufficient";
    items: { variant_id: string; requested: number; available: number }[];
  }
  | { status: "not_found" }
  | { status: "invalid_status" };

/** At order placement: hold every line or none (C-06c gets the shortfall). */
export async function reserveForOrder(
  deps: OrderStockDeps,
  orderId: string,
): Promise<ReserveResult> {
  const result = await deps.reserveStock(orderId);
  if (result.status === "reserved") {
    await alertLowStock(deps, result.low as LowStock[] | undefined);
    return { status: "reserved" };
  }
  return result as ReserveResult;
}

/** KHQR expiry, or cancel before packing: give the held units back. */
export async function releaseForOrder(
  deps: OrderStockDeps,
  orderId: string,
): Promise<{ status: "released"; units: number } | { status: "not_found" }> {
  return await deps.releaseStock(orderId) as
    | { status: "released"; units: number }
    | { status: "not_found" };
}

/** The goods left the store: held units become sold ones. */
export async function commitForOrder(
  deps: OrderStockDeps,
  orderId: string,
): Promise<
  { status: "committed"; units: number } | { status: "not_held" } | { status: "not_found" }
> {
  return await deps.commitStock(orderId) as
    | { status: "committed"; units: number }
    | { status: "not_held" }
    | { status: "not_found" };
}

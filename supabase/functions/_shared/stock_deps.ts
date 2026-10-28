// Real dependencies for inventory-manage and for the order flows that move
// stock: everything through the service role; adjust_stock acts as the
// calling staff member.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { notifyDeps } from "./notify_deps.ts";
import type { OrderStockDeps, StockDeps } from "./stock_flows.ts";
import type { StaffMember } from "./staff_flows.ts";

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

/** For checkout, payment, cancel and fulfilment functions (F17 – F20). */
export function orderStockDeps(service: SupabaseClient = serviceClient()): OrderStockDeps {
  async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await service.rpc(name, args);
    if (error) throw error;
    return data as T;
  }

  return {
    notify: notifyDeps(service),
    async lowStockRecipients() {
      return await rpc<string[]>("low_stock_recipients", {});
    },
    reserveStock: (orderId) => rpc("reserve_stock", { p_order: orderId }),
    releaseStock: (orderId) => rpc("release_stock", { p_order: orderId }),
    commitStock: (orderId) => rpc("commit_stock", { p_order: orderId }),
  };
}

export function stockDeps(): StockDeps {
  const service = serviceClient();
  const orders = orderStockDeps(service);

  return {
    notify: orders.notify,
    lowStockRecipients: orders.lowStockRecipients,
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
    async adjustStock(actorId, input) {
      const { data, error } = await service.rpc("adjust_stock", {
        p_actor: actorId,
        p_variant: input.variant_id,
        p_mode: input.mode,
        p_qty: input.qty,
        p_reason: input.reason,
        p_note: input.note ?? null,
        p_low_stock_at: input.low_stock_at ?? null,
      });
      if (error) throw error;
      return data as Record<string, unknown>;
    },
  };
}

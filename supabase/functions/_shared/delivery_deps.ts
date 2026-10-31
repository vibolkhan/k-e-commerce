import { createClient } from "@supabase/supabase-js";
import type { DeliveryDeps } from "./delivery_flows.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

export function deliveryDeps(): DeliveryDeps {
  const url = env("SUPABASE_URL");
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const service = createClient(url, env("SUPABASE_SERVICE_ROLE_KEY"), options);
  return {
    async userIdFor(authorization) {
      const token = authorization?.replace(/^Bearer\s+/i, "").trim();
      if (!token) return null;
      const { data, error } = await service.auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    async member(userId) {
      const { data, error } = await service.rpc("staff_member_info", { p_uid: userId }).maybeSingle();
      if (error) throw error;
      return data;
    },
    async quote(addressId, subtotalCents, authorization) {
      const user = createClient(url, env("SUPABASE_ANON_KEY"), {
        ...options,
        global: { headers: { Authorization: authorization } },
      });
      const { data, error } = await user.rpc("quote_delivery", {
        p_address: addressId,
        p_subtotal_cents: subtotalCents,
      });
      if (error) throw error;
      return data;
    },
    async saveZone(actorId, body) {
      const { data, error } = await service.rpc("update_delivery_zone", {
        p_actor: actorId,
        p_id: body.id,
        p_name: body.name,
        p_polygon: body.polygon,
        p_fee_cents: body.fee_cents,
        p_free_threshold_cents: body.free_threshold_cents,
        p_same_day: body.same_day,
        p_cod_enabled: body.cod_enabled,
        p_cod_limit_cents: body.cod_limit_cents,
        p_active: body.active,
      });
      if (error) throw error;
      return data;
    },
  };
}


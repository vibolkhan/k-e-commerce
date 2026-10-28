// Real dependencies for catalog-manage and catalog-import: everything through
// the service role; the SQL functions act as the calling staff member.

import { createClient } from "@supabase/supabase-js";
import type { CatalogDeps } from "./catalog_flows.ts";
import type { Category, ImportDeps } from "./import_flows.ts";
import type { StaffMember } from "./staff_flows.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

function serviceClient() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function catalogDeps(): CatalogDeps & ImportDeps {
  const service = serviceClient();

  async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await service.rpc(name, args);
    if (error) throw error;
    return data as T;
  }

  return {
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
    saveProduct: (actorId, product) =>
      rpc("catalog_save_product", { p_actor: actorId, p_product: product }),
    setStatus: (actorId, ids, status) =>
      rpc("catalog_set_status", { p_actor: actorId, p_ids: ids, p_status: status }),
    setCategory: (actorId, ids, categoryId) =>
      rpc("catalog_set_category", { p_actor: actorId, p_ids: ids, p_category: categoryId }),
    async categories() {
      const { data, error } = await service
        .from("categories")
        .select("id, slug, name, parent:parent_id (name)");
      if (error) throw error;
      return (data ?? []).map((c): Category => {
        const parent = c.parent as unknown as { name: { en: string } } | null;
        return {
          id: c.id as string,
          slug: c.slug as string,
          name_en: (c.name as { en: string }).en,
          parent_name_en: parent?.name.en ?? null,
        };
      });
    },
    existingSkus: async (skus) =>
      skus.length === 0 ? [] : await rpc<string[]>("catalog_existing_skus", { p_skus: skus }),
    async importProducts(actorId, products) {
      const result = await rpc<{ products: number }>("catalog_import", {
        p_actor: actorId,
        p_products: products,
      });
      return result.products;
    },
  };
}

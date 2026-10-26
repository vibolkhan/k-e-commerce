// Real dependencies for account-delete: everything through the service role.

import { createClient } from "@supabase/supabase-js";
import type { AccountDeps, DeletionCheck } from "./account_flows.ts";

/** Private buckets with files under `<uid>/` that go with the account. */
const PERSONAL_BUCKETS = ["business-docs", "chat-attachments"];

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set`);
  return value;
}

export function accountDeps(): AccountDeps {
  const service = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  /** Every file path under [folder], including sub-folders. */
  async function filesIn(bucket: string, folder: string): Promise<string[]> {
    const { data, error } = await service.storage.from(bucket).list(folder, { limit: 1000 });
    if (error) throw error;
    const paths: string[] = [];
    for (const entry of data ?? []) {
      const path = `${folder}/${entry.name}`;
      // Folders come back without an id.
      if (entry.id === null) paths.push(...await filesIn(bucket, path));
      else paths.push(path);
    }
    return paths;
  }

  return {
    async userIdFor(authorization) {
      const token = authorization?.replace(/^Bearer\s+/i, "").trim();
      if (!token) return null;
      const { data, error } = await service.auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    async deletionCheck(userId) {
      const { data, error } = await service.rpc("account_deletion_check", { p_uid: userId });
      if (error) throw error;
      return data as DeletionCheck;
    },
    async removeFiles(userId) {
      for (const bucket of PERSONAL_BUCKETS) {
        const paths = await filesIn(bucket, userId);
        if (paths.length === 0) continue;
        const { error } = await service.storage.from(bucket).remove(paths);
        if (error) throw error;
      }
    },
    async deleteUser(userId, reason) {
      // The deletion trigger reads the reason from app metadata.
      const { error: updateError } = await service.auth.admin.updateUserById(userId, {
        app_metadata: { deletion_reason: reason },
      });
      if (updateError) throw updateError;
      const { error } = await service.auth.admin.deleteUser(userId);
      if (error) throw error;
    },
  };
}

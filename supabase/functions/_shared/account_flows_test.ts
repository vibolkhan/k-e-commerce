import { assertEquals, assertRejects } from "@std/assert";
import { type AccountDeps, deleteAccount, type DeletionCheck } from "./account_flows.ts";
import { BadRequest, Unauthorized } from "./errors.ts";
import { handler } from "./http.ts";

// In-memory twin of auth + account_deletion_check, keyed by access token.
class FakeWorld implements AccountDeps {
  tokens = new Map([["t-dara", "u-dara"], ["t-vuthy", "u-vuthy"]]);
  checks = new Map<string, DeletionCheck>([
    ["u-dara", { role: "customer", active_orders: 0, open_returns: 0 }],
    ["u-vuthy", { role: "rider", active_orders: 0, open_returns: 0 }],
  ]);
  filesRemoved: string[] = [];
  deleted: { userId: string; reason: string | null }[] = [];

  userIdFor(authorization: string | null) {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    return Promise.resolve(this.tokens.get(token) ?? null);
  }
  deletionCheck(userId: string) {
    return Promise.resolve(
      this.checks.get(userId) ?? { role: null, active_orders: 0, open_returns: 0 },
    );
  }
  removeFiles(userId: string) {
    this.filesRemoved.push(userId);
    return Promise.resolve();
  }
  deleteUser(userId: string, reason: string | null) {
    this.deleted.push({ userId, reason });
    return Promise.resolve();
  }
}

const as = (token: string | null) =>
  new Request("http://x", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });

Deno.test("a customer with nothing open is deleted, files first", async () => {
  const w = new FakeWorld();
  const result = await deleteAccount(
    w,
    { reason: "  I don't use the app any more " },
    as("t-dara"),
  );
  assertEquals(result, { status: "deleted" });
  assertEquals(w.filesRemoved, ["u-dara"]);
  assertEquals(w.deleted, [{ userId: "u-dara", reason: "I don't use the app any more" }]);
});

Deno.test("business buyers can delete themselves too", async () => {
  const w = new FakeWorld();
  w.checks.set("u-dara", { role: "business", active_orders: 0, open_returns: 0 });
  assertEquals((await deleteAccount(w, {}, as("t-dara"))).status, "deleted");
});

Deno.test("an active order or open return blocks deletion", async () => {
  const w = new FakeWorld();
  w.checks.set("u-dara", { role: "customer", active_orders: 1, open_returns: 0 });
  assertEquals(await deleteAccount(w, {}, as("t-dara")), {
    status: "has_active_orders",
    active_orders: 1,
    open_returns: 0,
  });
  w.checks.set("u-dara", { role: "customer", active_orders: 0, open_returns: 2 });
  assertEquals((await deleteAccount(w, {}, as("t-dara"))).status, "has_active_orders");
  assertEquals(w.deleted, []);
  assertEquals(w.filesRemoved, []);
});

Deno.test("riders, staff and missing profiles are not allowed", async () => {
  const w = new FakeWorld();
  assertEquals(await deleteAccount(w, {}, as("t-vuthy")), { status: "not_allowed" });
  w.checks.set("u-dara", { role: "staff", active_orders: 0, open_returns: 0 });
  assertEquals((await deleteAccount(w, {}, as("t-dara"))).status, "not_allowed");
  w.checks.delete("u-dara");
  assertEquals((await deleteAccount(w, {}, as("t-dara"))).status, "not_allowed");
  assertEquals(w.deleted, []);
});

Deno.test("no or unknown session is unauthorized", async () => {
  const w = new FakeWorld();
  await assertRejects(() => deleteAccount(w, {}, as(null)), Unauthorized);
  await assertRejects(() => deleteAccount(w, {}, as("t-stolen")), Unauthorized);
});

Deno.test("reason is optional, trimmed and capped", async () => {
  const w = new FakeWorld();
  await deleteAccount(w, { reason: "   " }, as("t-dara"));
  await deleteAccount(w, { reason: "x".repeat(600) }, as("t-dara"));
  assertEquals(w.deleted[0].reason, null);
  assertEquals(w.deleted[1].reason?.length, 500);
  await assertRejects(() => deleteAccount(w, { reason: 42 }, as("t-dara")), BadRequest);
});

Deno.test("handler: 401 without a session, 200 with status otherwise", async () => {
  const w = new FakeWorld();
  const serve = handler(deleteAccount, () => w);
  const post = (token: string | null) =>
    serve(
      new Request("http://x", {
        method: "POST",
        headers: token ? { Authorization: `Bearer ${token}` } : {},
        body: "{}",
      }),
    );

  const denied = await post(null);
  assertEquals(denied.status, 401);
  assertEquals((await denied.json()).error, "unauthorized");

  const ok = await post("t-dara");
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).status, "deleted");
});

// F10 · Stock under concurrent checkouts, against the local stack.
//
// pgTAP runs in one session, so it cannot race two orders. These tests call
// the stock functions through PostgREST from many clients at once; every
// request is its own transaction, as two checkouts would be.
//
//   STOCK_IT=1 deno test --allow-net --allow-env _integration/
//
// Needs `supabase start` (or `db start` + API). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY default to the local stack. Everything the tests
// create is deleted at the end.

import { assert, assertEquals } from "@std/assert";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const enabled = Deno.env.get("STOCK_IT") === "1";
const url = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
// The local stack's well-known demo service key (supabase status).
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

const VISAL = "a0000000-0000-4000-8000-000000000004";
const DARA = "a0000000-0000-4000-8000-000000000021";

function client(): SupabaseClient {
  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

const db = client();

async function must<T>(query: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await query;
  if (error) throw new Error(JSON.stringify(error));
  return data;
}

/** A throwaway product with these variants and opening stock. */
async function makeProduct(tag: string, stock: Record<string, number>) {
  const category = await must(
    db.from("categories").select("id").eq("slug", "audio").single(),
  ) as { id: string };
  const saved = await must(db.rpc("catalog_save_product", {
    p_actor: VISAL,
    p_product: {
      category_id: category.id,
      slug: `race-${tag}`,
      name: { en: `Race test ${tag}` },
      description: {},
      highlights: [],
      specs: [],
      tags: [],
      options: [],
      status: "active",
      variants: Object.entries(stock).map(([suffix, qty]) => ({
        sku: `RACE-${tag}-${suffix}`,
        attributes: { v: suffix },
        price_cents: 1000,
        initial_qty: qty,
      })),
      images: [],
    },
  })) as { status: string; id: string };
  assertEquals(saved.status, "saved");
  const variants = await must(
    db.from("product_variants").select("id, sku").eq("product_id", saved.id),
  ) as { id: string; sku: string }[];
  const ids = Object.fromEntries(variants.map((v) => [v.sku.split("-").pop()!, v.id]));
  return { productId: saved.id, ids };
}

/** An order with these lines (variant id → qty), lines in the given order. */
async function makeOrder(
  productId: string,
  lines: [string, number][],
  method: "khqr" | "cod" = "cod",
): Promise<string> {
  const order = await must(
    db.from("orders").insert({
      profile_id: DARA,
      status: method === "khqr" ? "pending_payment" : "confirmed",
      payment_method: method,
      payment_status: method === "khqr" ? "pending" : "unpaid_cod",
      subtotal_cents: 100,
      total_cents: 100,
      address: {},
    }).select("id").single(),
  ) as { id: string };
  await must(
    db.from("order_items").insert(lines.map(([variantId, qty]) => ({
      order_id: order.id,
      variant_id: variantId,
      product_id: productId,
      name: { en: "Race test" },
      sku: "RACE",
      unit_price_cents: 100,
      qty,
    }))),
  );
  return order.id;
}

async function cleanUp(productId: string, orderIds: string[]) {
  for (let i = 0; i < orderIds.length; i += 100) {
    await must(db.from("orders").delete().in("id", orderIds.slice(i, i + 100)));
  }
  await must(db.from("products").delete().eq("id", productId));
}

async function stockOf(variantId: string) {
  return await must(
    db.from("stock").select("qty, reserved").eq("variant_id", variantId).single(),
  ) as { qty: number; reserved: number };
}

async function unitsByStatus(variantId: string) {
  const rows = await must(
    db.from("stock_reservations").select("qty, status").eq("variant_id", variantId),
  ) as { qty: number; status: string }[];
  const sum = (status: string) =>
    rows.filter((r) => r.status === status).reduce((n, r) => n + r.qty, 0);
  return { held: sum("held"), committed: sum("committed") };
}

/** Calls a stock function from its own client, as a separate checkout would. */
async function call(name: string, orderId: string): Promise<Record<string, unknown>> {
  return await must(client().rpc(name, { p_order: orderId })) as Record<string, unknown>;
}

function tag() {
  return crypto.randomUUID().slice(0, 8).toUpperCase();
}

Deno.test({
  name: "two orders for the last unit at the same moment: exactly one gets it",
  ignore: !enabled,
  async fn() {
    const t = tag();
    const { productId, ids } = await makeProduct(t, { ONE: 1 });
    const orders: string[] = [];
    try {
      for (let round = 0; round < 10; round++) {
        const a = await makeOrder(productId, [[ids.ONE, 1]]);
        const b = await makeOrder(productId, [[ids.ONE, 1]]);
        orders.push(a, b);

        const results = await Promise.all([call("reserve_stock", a), call("reserve_stock", b)]);
        const statuses = results.map((r) => r.status).sort();
        assertEquals(statuses, ["insufficient", "reserved"], `round ${round}`);
        assertEquals(await stockOf(ids.ONE), { qty: 1, reserved: 1 });

        // Give the unit back for the next round.
        const winner = results[0].status === "reserved" ? a : b;
        assertEquals((await call("release_stock", winner)).units, 1);
      }
    } finally {
      await cleanUp(productId, orders);
    }
  },
});

Deno.test({
  name: "under load, available = on hand − reserved and nothing oversells",
  ignore: !enabled,
  async fn() {
    const t = tag();
    const start = { A: 50, B: 30 };
    const { productId, ids } = await makeProduct(t, start);
    const orders: string[] = [];
    try {
      // 150 orders of 1–3 units; half of them take both variants, listed in
      // either order, which deadlocks if locks are not taken in one order.
      for (let i = 0; i < 150; i++) {
        const qa = 1 + (i % 3);
        const qb = 1 + ((i * 7) % 3);
        const lines: [string, number][] = i % 2 === 0
          ? [[ids.A, qa]]
          : i % 4 === 1
          ? [[ids.A, qa], [ids.B, qb]]
          : [[ids.B, qb], [ids.A, qa]];
        orders.push(await makeOrder(productId, lines));
      }

      const reserved: string[] = [];
      const tally = { reserved: 0, insufficient: 0 };
      // Round 1: everyone checks out at once (in waves of 30 requests).
      for (let i = 0; i < orders.length; i += 30) {
        const wave = orders.slice(i, i + 30);
        const results = await Promise.all(wave.map((id) => call("reserve_stock", id)));
        results.forEach((r, j) => {
          const status = r.status as keyof typeof tally;
          assert(status in tally, `unexpected ${JSON.stringify(r)}`);
          tally[status]++;
          if (status === "reserved") reserved.push(wave[j]);
        });
      }
      assert(tally.reserved > 0 && tally.insufficient > 0, JSON.stringify(tally));

      // Round 2: some pay and ship, some cancel, and the refused ones retry,
      // all at the same time.
      const commits = reserved.filter((_, i) => i % 3 === 0);
      const releases = reserved.filter((_, i) => i % 3 === 1);
      const retries = orders.filter((id) => !reserved.includes(id));
      await Promise.all([
        ...commits.map((id) => call("commit_stock", id)),
        ...releases.map((id) => call("release_stock", id)),
        ...retries.map((id) => call("reserve_stock", id)),
      ]);

      for (const [key, variantId] of Object.entries(ids)) {
        const stock = await stockOf(variantId);
        const units = await unitsByStatus(variantId);
        const initial = start[key as keyof typeof start];
        assertEquals(stock.reserved, units.held, `${key}: reserved = units held by orders`);
        assertEquals(stock.qty, initial - units.committed, `${key}: on hand = start − shipped`);
        assert(stock.qty - stock.reserved >= 0, `${key}: available never goes below zero`);
        assert(units.held + units.committed <= initial, `${key}: never sold more than there was`);
      }
    } finally {
      await cleanUp(productId, orders);
    }
  },
});

Deno.test({
  name: "the expiry job gives back an unpaid KHQR hold",
  ignore: !enabled,
  async fn() {
    const t = tag();
    const { productId, ids } = await makeProduct(t, { X: 5 });
    const orders: string[] = [];
    try {
      const order = await makeOrder(productId, [[ids.X, 4]], "khqr");
      orders.push(order);
      assertEquals((await call("reserve_stock", order)).status, "reserved");
      const held = await must(
        db.from("orders").select("reserved_until").eq("id", order).single(),
      ) as { reserved_until: string };
      const minutes = (Date.parse(held.reserved_until) - Date.now()) / 60_000;
      assert(minutes > 14 && minutes <= 15, `held for ${minutes} minutes`);

      await must(
        db.from("orders").update({ reserved_until: new Date(Date.now() - 60_000).toISOString() })
          .eq("id", order),
      );
      // The cron job may beat us to it; either way the units come back.
      await must(db.rpc("release_expired_reservations"));
      assertEquals(await stockOf(ids.X), { qty: 5, reserved: 0 });
      assertEquals(await unitsByStatus(ids.X), { held: 0, committed: 0 });
    } finally {
      await cleanUp(productId, orders);
    }
  },
});

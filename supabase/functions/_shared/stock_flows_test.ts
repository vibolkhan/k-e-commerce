import { assertEquals, assertRejects } from "@std/assert";
import { BadRequest, Unauthorized } from "./errors.ts";
import type { NewNotification, NotifyDeps } from "./notify_flows.ts";
import type { StaffMember, StaffRole } from "./staff_flows.ts";
import {
  type AdjustInput,
  checkAdjust,
  type LowStock,
  manageInventory,
  type OrderStockDeps,
  reserveForOrder,
  type StockDeps,
} from "./stock_flows.ts";

const VARIANT = "33333333-3333-4333-8333-333333333333";
const ORDER = "44444444-4444-4444-8444-444444444444";
const STAFF = ["55555555-5555-4555-8555-555555555555", "66666666-6666-4666-8666-666666666666"];

const LAMP: LowStock = {
  variant_id: VARIANT,
  sku: "LMP-LED-WHT",
  product_name: "LED Desk Lamp · White",
  available: 3,
  threshold: 10,
};

// Notify plumbing that keeps the inbox rows in memory.
class FakeNotify implements NotifyDeps {
  inbox: NewNotification[] = [];
  failing = false;
  push = { send: () => Promise.resolve("sent" as const) };
  recipients(ids: string[]) {
    return Promise.resolve(ids.map((id) => ({
      id,
      role: "staff" as const,
      locale: "en" as const,
      prefs: {},
    })));
  }
  insertNotifications(rows: NewNotification[]) {
    if (this.failing) return Promise.reject(new Error("inbox down"));
    this.inbox.push(...rows);
    return Promise.resolve(rows.map((_, i) => `n${this.inbox.length + i}`));
  }
  unreadCounts() {
    return Promise.resolve(new Map<string, number>());
  }
  tokens() {
    return Promise.resolve([]);
  }
  deleteTokens() {
    return Promise.resolve();
  }
}

// In-memory twin of auth, staff and the stock SQL functions.
class FakeWorld implements StockDeps, OrderStockDeps {
  tokens = new Map([["t-visal", "u-visal"], ["t-chenda", "u-chenda"], ["t-dalin", "u-dalin"]]);
  members = new Map<string, StaffMember>([
    ["u-visal", member("u-visal", "catalog")],
    ["u-chenda", member("u-chenda", "super_admin")],
    ["u-dalin", member("u-dalin", "sales")],
  ]);
  notify = new FakeNotify();
  adjusted: { actor: string; input: AdjustInput }[] = [];
  nextAdjust: Record<string, unknown> = {
    status: "adjusted",
    on_hand: 54,
    reserved: 1,
    available: 53,
    low_stock_at: 10,
    delta: 50,
    low: [],
  };
  nextReserve: Record<string, unknown> = { status: "reserved", low: [] };

  userIdFor(authorization: string | null) {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    return Promise.resolve(this.tokens.get(token) ?? null);
  }
  member(profileId: string) {
    return Promise.resolve(this.members.get(profileId) ?? null);
  }
  lowStockRecipients() {
    return Promise.resolve(STAFF);
  }
  adjustStock(actor: string, input: AdjustInput) {
    this.adjusted.push({ actor, input });
    return Promise.resolve(this.nextAdjust);
  }
  reserveStock() {
    return Promise.resolve(this.nextReserve);
  }
  releaseStock() {
    return Promise.resolve({ status: "released", units: 2 });
  }
  commitStock() {
    return Promise.resolve({ status: "committed", units: 2 });
  }
}

function member(id: string, role: StaffRole): StaffMember {
  return {
    profile_id: id,
    full_name: id,
    email: null,
    phone: null,
    staff_role: role,
    status: "active",
  };
}

function req(token?: string) {
  return new Request("http://local/inventory-manage", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
}

const adjust = (extra: Record<string, unknown> = {}) => ({
  action: "adjust",
  variant_id: VARIANT,
  mode: "add",
  qty: 50,
  reason: "received",
  note: "  Delivery note DN-2210 from supplier ",
  ...extra,
});

Deno.test("catalog staff add stock as themselves, with the note trimmed", async () => {
  const world = new FakeWorld();
  const result = await manageInventory(world, adjust(), req("t-visal"));
  assertEquals(result, {
    status: "adjusted",
    on_hand: 54,
    reserved: 1,
    available: 53,
    low_stock_at: 10,
    delta: 50,
  });
  assertEquals(world.adjusted, [{
    actor: "u-visal",
    input: {
      variant_id: VARIANT,
      mode: "add",
      qty: 50,
      reason: "received",
      note: "Delivery note DN-2210 from supplier",
    },
  }]);
});

Deno.test("super admins may adjust; sales may only look", async () => {
  const world = new FakeWorld();
  assertEquals((await manageInventory(world, adjust(), req("t-chenda"))).status, "adjusted");
  assertEquals(await manageInventory(world, adjust(), req("t-dalin")), { status: "forbidden" });
  assertEquals(world.adjusted.length, 1);
});

Deno.test("no session is 401, an unknown action is 400", async () => {
  const world = new FakeWorld();
  await assertRejects(() => manageInventory(world, adjust(), req()), Unauthorized);
  await assertRejects(
    () => manageInventory(world, { action: "reserve" }, req("t-visal")),
    BadRequest,
  );
});

Deno.test("a bad body lists every field that is wrong", () => {
  assertEquals(checkAdjust({}), {
    errors: [
      { field: "variant_id", code: "required" },
      { field: "mode", code: "required" },
      { field: "qty", code: "required" },
      { field: "reason", code: "required" },
    ],
  });
  assertEquals(
    checkAdjust(adjust({ qty: 1.5, note: "x".repeat(501), low_stock_at: -1 })),
    {
      errors: [
        { field: "qty", code: "invalid" },
        { field: "note", code: "too_long" },
        { field: "low_stock_at", code: "invalid" },
      ],
    },
  );
});

Deno.test("each mode only takes its own reasons", () => {
  assertEquals(checkAdjust(adjust({ reason: "damaged" })), {
    errors: [{ field: "reason", code: "invalid" }],
  });
  assertEquals(checkAdjust(adjust({ mode: "remove", qty: 2, reason: "received" })), {
    errors: [{ field: "reason", code: "invalid" }],
  });
  assertEquals("errors" in checkAdjust(adjust({ mode: "remove", reason: "damaged" })), false);
  assertEquals(checkAdjust(adjust({ mode: "set", qty: 7, reason: "received" })), {
    errors: [{ field: "reason", code: "invalid" }],
  });
});

Deno.test("adding zero is refused, but a count may be set to zero", () => {
  assertEquals(checkAdjust(adjust({ qty: 0 })), { errors: [{ field: "qty", code: "invalid" }] });
  assertEquals(
    checkAdjust(adjust({ mode: "set", qty: 0, reason: "adjustment", note: undefined })),
    { variant_id: VARIANT, mode: "set", qty: 0, reason: "adjustment" },
  );
});

Deno.test("database outcomes pass through", async () => {
  const world = new FakeWorld();
  world.nextAdjust = { status: "below_reserved", reserved: 2 };
  assertEquals(await manageInventory(world, adjust(), req("t-visal")), {
    status: "below_reserved",
    reserved: 2,
  });
  world.nextAdjust = { status: "not_found" };
  assertEquals(await manageInventory(world, adjust(), req("t-visal")), { status: "not_found" });
  world.nextAdjust = { status: "invalid", field: "reason" };
  assertEquals(await manageInventory(world, adjust(), req("t-visal")), {
    status: "invalid",
    errors: [{ field: "reason", code: "invalid" }],
  });
});

Deno.test("falling to the alert level tells catalog staff", async () => {
  const world = new FakeWorld();
  world.nextAdjust = { ...world.nextAdjust, low: [LAMP] };
  await manageInventory(world, adjust({ mode: "remove", reason: "damaged" }), req("t-visal"));
  assertEquals(world.notify.inbox.map((n) => [n.profile_id, n.type, n.body.en, n.payload.route]), [
    [
      STAFF[0],
      "admin_low_stock",
      "LED Desk Lamp · White has 3 left. Low-stock level is 10.",
      "/admin/inventory",
    ],
    [
      STAFF[1],
      "admin_low_stock",
      "LED Desk Lamp · White has 3 left. Low-stock level is 10.",
      "/admin/inventory",
    ],
  ]);
});

Deno.test("a failed alert does not fail the adjustment", async () => {
  const world = new FakeWorld();
  world.nextAdjust = { ...world.nextAdjust, low: [LAMP] };
  world.notify.failing = true;
  assertEquals((await manageInventory(world, adjust(), req("t-visal"))).status, "adjusted");
});

Deno.test("reserving an order alerts on crossings and passes shortfalls back", async () => {
  const world = new FakeWorld();
  world.nextReserve = { status: "reserved", low: [LAMP] };
  assertEquals(await reserveForOrder(world, ORDER), { status: "reserved" });
  assertEquals(world.notify.inbox.length, 2);

  const short: Record<string, unknown> = {
    status: "insufficient",
    items: [{ variant_id: VARIANT, requested: 2, available: 1 }],
  };
  world.nextReserve = short;
  assertEquals(await reserveForOrder(world, ORDER), short);
  assertEquals(world.notify.inbox.length, 2);
});

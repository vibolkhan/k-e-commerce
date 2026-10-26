import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { BadRequest, Unauthorized } from "./errors.ts";
import { handler } from "./http.ts";
import {
  type Caller,
  type DeviceToken,
  type NewNotification,
  notify,
  type NotifyHttpDeps,
  notifyRequest,
  type Profile,
  type PushMessage,
  type PushResult,
} from "./notify_flows.ts";
import { format, NOTIFICATION_TYPES, render, requiredKeys } from "./notify_types.ts";

const DARA = "a0000000-0000-4000-8000-000000000021";
const SOKHA = "a0000000-0000-4000-8000-000000000031";
const VUTHY = "a0000000-0000-4000-8000-000000000011";
const GONE = "a0000000-0000-4000-8000-000000000099";
const ORDER = "d0000000-0000-4000-8000-000000010248";
const RFQ = "b0000000-0000-4000-8000-000000000312";

// In-memory twin of profiles, notifications, device_tokens and FCM.
class FakeWorld implements NotifyHttpDeps {
  profiles = new Map<string, Profile>([
    [DARA, { id: DARA, role: "customer", locale: "en", prefs: {} }],
    [SOKHA, { id: SOKHA, role: "business", locale: "km", prefs: {} }],
    [VUTHY, { id: VUTHY, role: "rider", locale: "en", prefs: {} }],
  ]);
  inbox: (NewNotification & { id: string; read: boolean })[] = [];
  devices: DeviceToken[] = [
    { profile_id: DARA, token: "dara-phone", platform: "android" },
    { profile_id: DARA, token: "dara-web", platform: "web" },
    { profile_id: SOKHA, token: "sokha-iphone", platform: "ios" },
    { profile_id: VUTHY, token: "vuthy-phone", platform: "android" },
  ];
  sent: PushMessage[] = [];
  results = new Map<string, PushResult>();
  slept: number[] = [];
  selfTestEnabled = true;
  sessions = new Map<string, Caller>([
    ["service-key", { kind: "service" }],
    ["t-dara", { kind: "user", id: DARA }],
  ]);

  push = {
    send: (msg: PushMessage) => {
      this.sent.push(msg);
      return Promise.resolve(this.results.get(msg.token) ?? "sent");
    },
  };

  recipients(ids: string[]) {
    return Promise.resolve(ids.flatMap((id) => this.profiles.get(id) ?? []));
  }
  insertNotifications(rows: NewNotification[]) {
    const ids = rows.map((row, i) => {
      const id = `n-${this.inbox.length + i + 1}`;
      return id;
    });
    rows.forEach((row, i) => this.inbox.push({ ...row, id: ids[i], read: false }));
    return Promise.resolve(ids);
  }
  unreadCounts(ids: string[]) {
    const counts = new Map<string, number>();
    for (const n of this.inbox) {
      if (ids.includes(n.profile_id) && !n.read) {
        counts.set(n.profile_id, (counts.get(n.profile_id) ?? 0) + 1);
      }
    }
    return Promise.resolve(counts);
  }
  tokens(ids: string[]) {
    return Promise.resolve(this.devices.filter((d) => ids.includes(d.profile_id)));
  }
  deleteTokens(tokens: string[]) {
    this.devices = this.devices.filter((d) => !tokens.includes(d.token));
    return Promise.resolve();
  }
  callerFor(authorization: string | null) {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    return Promise.resolve(this.sessions.get(token) ?? null);
  }
  sleep(ms: number) {
    this.slept.push(ms);
    return Promise.resolve();
  }
}

const as = (token: string | null) =>
  new Request("http://x", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });

const paid = { order_id: ORDER, order_number: "K-10248", amount: 9200 };

// ---------------------------------------------------------------- notify

Deno.test("writes the inbox row and pushes every device, in the person's language", async () => {
  const w = new FakeWorld();
  const result = await notify(w, [DARA], "payment_received", paid);
  assertEquals(result, { status: "sent", inbox: 1, pushed: 2, skipped: 0 });

  const [row] = w.inbox;
  assertEquals(row.category, "orders");
  assertEquals(row.title, { en: "Payment received", km: "បានទទួលការទូទាត់" });
  assertEquals(
    row.body.en,
    "We got $92.00 by KHQR for #K-10248. Your order is confirmed.",
  );
  assertEquals(row.payload.route, `/customer/orders/${ORDER}`);
  assertEquals(row.payload.order_id, ORDER);

  assertEquals(w.sent.map((m) => m.token), ["dara-phone", "dara-web"]);
  assertEquals(w.sent[0].title, "Payment received");
  assertEquals(w.sent[0].data, {
    type: "payment_received",
    route: `/customer/orders/${ORDER}`,
    notification_id: "n-1",
  });
  assertEquals(w.sent[0].badge, 1);
});

Deno.test("a Khmer reader gets the push in Khmer", async () => {
  const w = new FakeWorld();
  await notify(w, [SOKHA], "quote_ready", {
    rfq_id: RFQ,
    rfq_number: "RFQ-0312",
    amount: 226050,
    valid_until: "2026-11-05",
  });
  assertEquals(w.sent[0].title, "សម្រង់តម្លៃរបស់អ្នករួចរាល់ហើយ");
  assertEquals(
    w.sent[0].body,
    "RFQ-0312 · $2,260.50 · មានសុពលភាពដល់ 5 វិច្ឆិកា។ ពិនិត្យ និងទទួលយក។",
  );
  assertEquals(
    w.inbox[0].body.en,
    "RFQ-0312 · $2,260.50 · valid until 5 Nov. Review and accept.",
  );
  assertEquals(w.inbox[0].payload.route, `/business/quotes/${RFQ}`);
  assertEquals(w.inbox[0].category, "quotes");
});

Deno.test("order links open in the recipient's own shell", async () => {
  const w = new FakeWorld();
  await notify(w, [DARA, SOKHA], "bank_transfer_confirmed", paid);
  assertEquals(w.inbox.map((n) => n.payload.route), [
    `/customer/orders/${ORDER}`,
    `/business/orders/${ORDER}`,
  ]);
});

Deno.test("a switched-off kind still reaches the inbox but sends no push", async () => {
  const w = new FakeWorld();
  w.profiles.get(DARA)!.prefs = { orders: { push: false, email: true } };
  const result = await notify(w, [DARA], "order_packing", paid);
  assertEquals(result, { status: "sent", inbox: 1, pushed: 0, skipped: 1 });
  assertEquals(w.sent, []);
});

Deno.test("payments are always sent, whatever the switches say", async () => {
  const w = new FakeWorld();
  w.profiles.get(DARA)!.prefs = { orders: { push: false } };
  const result = await notify(w, [DARA], "payment_received", paid);
  assertEquals(result.pushed, 2);
});

Deno.test("review reminders are off until turned on", async () => {
  const w = new FakeWorld();
  const data = { order_id: ORDER, order_number: "K-10248", product_name: "Running Sneakers Air" };
  assertEquals((await notify(w, [DARA], "review_reminder", data)).pushed, 0);
  w.profiles.get(DARA)!.prefs = { reviews: { push: true } };
  assertEquals((await notify(w, [DARA], "review_reminder", data)).pushed, 2);
  assertEquals(w.inbox.length, 2);
});

Deno.test("dead tokens are forgotten; a failed send is not", async () => {
  const w = new FakeWorld();
  w.results.set("dara-phone", "invalid_token");
  w.results.set("dara-web", "failed");
  const result = await notify(w, [DARA], "payment_received", paid);
  assertEquals(result, { status: "sent", inbox: 1, pushed: 0, skipped: 1 });
  assertEquals(w.devices.map((d) => d.token), ["dara-web", "sokha-iphone", "vuthy-phone"]);
});

Deno.test("unknown, deleted or blocked people are skipped", async () => {
  const w = new FakeWorld();
  const result = await notify(w, [GONE, DARA, DARA], "payment_received", paid);
  assertEquals(result, { status: "sent", inbox: 1, pushed: 2, skipped: 1 });
  assertEquals(
    await notify(w, [GONE], "payment_received", paid),
    { status: "sent", inbox: 0, pushed: 0, skipped: 1 },
  );
});

Deno.test("rider job alerts play the job sound and open the rider app", async () => {
  const w = new FakeWorld();
  await notify(w, [VUTHY], "job_assigned", { order_number: "K-10264", area: "Toul Kork" });
  assertEquals(w.sent[0].sound, "job");
  assertEquals(w.sent[0].data.route, "/rider");
  assertEquals(w.sent[0].body, "#K-10264 · Toul Kork. Tap to view the job.");
});

Deno.test("bad input is refused before anything is written", async () => {
  const w = new FakeWorld();
  await assertRejects(() => notify(w, [DARA], "nope", {}), BadRequest, "unknown type");
  await assertRejects(
    () => notify(w, [DARA], "payment_received", { order_id: ORDER }),
    BadRequest,
    "data is missing amount, order_number",
  );
  await assertRejects(
    () => notify(w, [DARA], "payment_received", { ...paid, order_id: "../admin" }),
    BadRequest,
    "order_id must be a uuid",
  );
  await assertRejects(
    () => notify(w, [DARA], "payment_received", { ...paid, amount: "92" + "x" }),
    BadRequest,
    "not cents",
  );
  await assertRejects(() => notify(w, [], "payment_received", paid), BadRequest, "user_ids");
  await assertRejects(() => notify(w, ["dara"], "payment_received", paid), BadRequest, "uuids");
  assertEquals(w.inbox, []);
  assertEquals(w.sent, []);
});

// ---------------------------------------------------------------- HTTP

Deno.test("the service role may notify anyone", async () => {
  const w = new FakeWorld();
  const result = await notifyRequest(
    w,
    { user_ids: [DARA], type: "payment_received", data: paid },
    as("service-key"),
  );
  assertEquals(result.inbox, 1);
});

Deno.test("users may only send themselves a test, and only when self-test is on", async () => {
  const w = new FakeWorld();
  await assertRejects(
    () =>
      notifyRequest(w, { user_ids: [SOKHA], type: "payment_received", data: paid }, as("t-dara")),
    Unauthorized,
  );
  await assertRejects(() => notifyRequest(w, { type: "test" }, as(null)), Unauthorized);

  const result = await notifyRequest(
    w,
    {
      type: "test",
      user_ids: [SOKHA],
      data: { target: "order", order_id: ORDER, delay_seconds: 5 },
    },
    as("t-dara"),
  );
  assertEquals(result.inbox, 1);
  assertEquals(w.inbox[0].profile_id, DARA);
  assertEquals(w.inbox[0].payload.route, `/customer/orders/${ORDER}`);
  assertEquals(w.inbox[0].category, "account");
  assertEquals(w.slept, [5000]);

  w.selfTestEnabled = false;
  await assertRejects(() => notifyRequest(w, { type: "test" }, as("t-dara")), Unauthorized);
});

Deno.test("a test opens the inbox by default, or the target asked for", async () => {
  const w = new FakeWorld();
  await notifyRequest(w, { type: "test" }, as("t-dara"));
  await notifyRequest(w, { type: "test", data: { target: "quote", rfq_id: RFQ } }, as("t-dara"));
  assertEquals(w.inbox.map((n) => n.payload.route), ["/customer/inbox", `/business/quotes/${RFQ}`]);
  await assertRejects(
    () => notifyRequest(w, { type: "test", data: { target: "chat" } }, as("t-dara")),
    BadRequest,
    "conversation_id must be a uuid",
  );
  await assertRejects(
    () => notifyRequest(w, { type: "test", data: { target: "admin" } }, as("t-dara")),
    BadRequest,
    "target must be one of",
  );
  await assertRejects(
    () => notifyRequest(w, { type: "test", data: { delay_seconds: 60 } }, as("t-dara")),
    BadRequest,
    "delay_seconds",
  );
  assertEquals(w.slept, []);
});

Deno.test("over HTTP: 401 without a session, 400 for bad data, 200 when sent", async () => {
  const w = new FakeWorld();
  const serve = handler(notifyRequest, () => w);
  const post = (token: string | null, body: unknown) =>
    serve(
      new Request("http://x", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
      }),
    );
  assertEquals((await post(null, { type: "test" })).status, 401);
  assertEquals((await post("service-key", { user_ids: "x", type: "test" })).status, 400);
  const ok = await post("service-key", { user_ids: [DARA], type: "test" });
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).status, "sent");
});

// ---------------------------------------------------------------- copy

Deno.test("formats money, dates and times in Phnom Penh time", () => {
  assertEquals(format(9200, "money", "en"), "$92.00");
  assertEquals(format(226050, "money", "km"), "$2,260.50");
  assertEquals(format(5, "money", "en"), "$0.05");
  assertEquals(format("2026-11-05", "date", "en"), "5 Nov");
  assertEquals(format("2026-10-25", "day", "en"), "Sun 25 Oct");
  assertEquals(format("2026-10-25", "day", "km"), "អាទិត្យ 25 តុលា");
  // 07:01 UTC is 2:01 PM in Phnom Penh; 17:30 UTC is past midnight there.
  assertEquals(format("2026-10-22T07:01:00Z", "time", "en"), "2:01 PM");
  assertEquals(format("2026-10-22T17:30:00Z", "date", "en"), "23 Oct");
  assertEquals(format("2026-10-22T05:00:00Z", "time", "en"), "12:00 PM");
  assertThrows(() => format("soon", "date", "en"), TypeError);
});

Deno.test("every type has both languages with the same placeholders", () => {
  const keys = (text: string) => [...text.matchAll(/\{(\w+)(?::\w+)?\}/g)].map((m) => m[0]).sort();
  for (const [name, type] of Object.entries(NOTIFICATION_TYPES)) {
    for (const part of ["title", "body"] as const) {
      assertEquals(keys(type[part].km), keys(type[part].en), `${name}.${part}`);
    }
    // Rendering with dummy values never leaves a placeholder behind.
    const data = Object.fromEntries(
      requiredKeys(type).map((
        k,
      ) => [
        k,
        /amount|fee/.test(k) ? 100 : /date|until|deadline|_at$/.test(k) ? "2026-11-05" : "x",
      ]),
    );
    for (const locale of ["en", "km"] as const) {
      const text = render(type.body[locale], data, locale);
      assertEquals(text.includes("{"), false, `${name} ${locale}: ${text}`);
    }
  }
});

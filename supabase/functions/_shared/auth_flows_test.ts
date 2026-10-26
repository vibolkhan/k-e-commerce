import { assertEquals, assertRejects } from "@std/assert";
import {
  type AttemptKind,
  type AttemptState,
  type AuthDeps,
  type AuthSession,
  BadRequest,
  passwordSignIn,
  sendOtp,
  verifyOtp,
} from "./auth_flows.ts";
import { handler } from "./http.ts";
import { normalizeEmail, normalizeKhPhone } from "./phone.ts";

const GOOD_CODE = "123456";
const GOOD_PASSWORD = "password123";

// In-memory twin of public.auth_attempt_* (5 tries, 15 min, 60 s).
class FakeWorld implements AuthDeps {
  now = 0;
  counters = new Map<
    string,
    { failed: number; lockedUntil: number | null; sentAt: number | null }
  >();
  sent: string[] = [];
  signedOut: string[] = [];
  blockedUsers = new Set<string>();
  names = new Map<string, string>([["u-dara", "Dara Sok"]]);
  smsWorks = true;

  private row(kind: AttemptKind, id: string) {
    const key = `${kind}:${id}`;
    if (!this.counters.has(key)) {
      this.counters.set(key, { failed: 0, lockedUntil: null, sentAt: null });
    }
    return this.counters.get(key)!;
  }
  private state(kind: AttemptKind, id: string): AttemptState {
    const r = this.row(kind, id);
    if (r.lockedUntil !== null && r.lockedUntil <= this.now) {
      Object.assign(r, { failed: 0, lockedUntil: null });
    }
    return {
      locked_until: r.lockedUntil === null ? null : new Date(r.lockedUntil).toISOString(),
      tries_left: Math.max(5 - r.failed, 0),
      resend_in: r.sentAt === null
        ? 0
        : Math.max(0, Math.ceil((r.sentAt + 60_000 - this.now) / 1000)),
    };
  }

  attempts = {
    status: (kind: AttemptKind, id: string) => Promise.resolve(this.state(kind, id)),
    fail: (kind: AttemptKind, id: string) => {
      const r = this.row(kind, id);
      r.failed++;
      if (r.failed >= 5 && r.lockedUntil === null) r.lockedUntil = this.now + 15 * 60_000;
      return Promise.resolve(this.state(kind, id));
    },
    reset: (kind: AttemptKind, id: string) => {
      Object.assign(this.row(kind, id), { failed: 0, lockedUntil: null });
      return Promise.resolve();
    },
    markSent: (kind: AttemptKind, id: string) => {
      this.row(kind, id).sentAt = this.now;
      return Promise.resolve();
    },
  };

  private session(userId: string): AuthSession {
    return {
      access_token: `at-${userId}`,
      refresh_token: `rt-${userId}`,
      expires_in: 3600,
      user_id: userId,
    };
  }
  private userFor(id: string) {
    return id === "+85512345678" || id === "dara@kstore.example"
      ? "u-dara"
      : id === "+85512345680"
      ? "u-vannak"
      : "u-new";
  }

  auth = {
    sendOtp: (phone: string) => {
      if (this.smsWorks) this.sent.push(phone);
      return Promise.resolve(this.smsWorks ? null : "phone_provider_disabled");
    },
    verifyOtp: (phone: string, token: string) =>
      Promise.resolve(token === GOOD_CODE ? this.session(this.userFor(phone)) : null),
    signInWithPassword: (email: string, password: string) =>
      Promise.resolve(password === GOOD_PASSWORD ? this.session(this.userFor(email)) : null),
    signOut: (token: string) => {
      this.signedOut.push(token);
      return Promise.resolve();
    },
  };

  profiles = {
    byId: (userId: string) =>
      Promise.resolve(
        userId === "u-new" && !this.names.has(userId) ? { is_blocked: false, full_name: null } : {
          is_blocked: this.blockedUsers.has(userId),
          full_name: this.names.get(userId) ?? null,
        },
      ),
    isPhoneBlocked: (phone: string) => Promise.resolve(this.blockedUsers.has(this.userFor(phone))),
  };
}

Deno.test("phone numbers normalise to +855", () => {
  assertEquals(normalizeKhPhone("012 345 678"), "+85512345678");
  assertEquals(normalizeKhPhone("12345678"), "+85512345678");
  assertEquals(normalizeKhPhone("+855 12 345 678"), "+85512345678");
  assertEquals(normalizeKhPhone("855-97-123-4567"), "+855971234567");
  assertEquals(normalizeKhPhone("1234"), null);
  assertEquals(normalizeKhPhone("+1 415 555 0100"), null);
  assertEquals(normalizeKhPhone("12abc678"), null);
  assertEquals(normalizeEmail(" Dara@KStore.example "), "dara@kstore.example");
  assertEquals(normalizeEmail("nope"), null);
});

Deno.test("send: sends once, then waits 60 s", async () => {
  const w = new FakeWorld();
  assertEquals(await sendOtp(w, { phone: "012 345 678" }), { status: "sent", resend_in: 60 });
  assertEquals(w.sent, ["+85512345678"]);
  w.now += 42_000;
  assertEquals(await sendOtp(w, { phone: "12345678" }), {
    status: "resend_too_soon",
    resend_in: 18,
  });
  w.now += 18_000;
  assertEquals((await sendOtp(w, { phone: "12345678" })).status, "sent");
});

Deno.test("send: refuses blocked numbers before texting", async () => {
  const w = new FakeWorld();
  w.blockedUsers.add("u-vannak");
  assertEquals(await sendOtp(w, { phone: "12345680" }), { status: "blocked" });
  assertEquals(w.sent, []);
});

Deno.test("send: provider failure does not start the resend clock", async () => {
  const w = new FakeWorld();
  w.smsWorks = false;
  assertEquals(await sendOtp(w, { phone: "12345678" }), {
    status: "send_failed",
    reason: "phone_provider_disabled",
  });
  w.smsWorks = true;
  assertEquals((await sendOtp(w, { phone: "12345678" })).status, "sent");
});

Deno.test("verify: wrong codes count down, the 5th locks for 15 minutes", async () => {
  const w = new FakeWorld();
  for (const left of [4, 3, 2, 1]) {
    assertEquals(await verifyOtp(w, { phone: "12345678", token: "000000" }), {
      status: "invalid_code",
      tries_left: left,
    });
  }
  const fifth = await verifyOtp(w, { phone: "12345678", token: "000000" });
  assertEquals(fifth.status, "locked");

  // Even the right code is refused while locked, and so is a new code.
  assertEquals((await verifyOtp(w, { phone: "12345678", token: GOOD_CODE })).status, "locked");
  assertEquals((await sendOtp(w, { phone: "12345678" })).status, "locked");

  w.now += 15 * 60_000;
  assertEquals((await verifyOtp(w, { phone: "12345678", token: GOOD_CODE })).status, "signed_in");
});

Deno.test("verify: right code signs in and clears failures", async () => {
  const w = new FakeWorld();
  await verifyOtp(w, { phone: "12345678", token: "000000" });
  const ok = await verifyOtp(w, { phone: "12345678", token: GOOD_CODE });
  assertEquals(ok, {
    status: "signed_in",
    session: {
      access_token: "at-u-dara",
      refresh_token: "rt-u-dara",
      expires_in: 3600,
      user_id: "u-dara",
    },
    is_new_user: false,
  });
  assertEquals(
    await verifyOtp(w, { phone: "12345678", token: "000000" }),
    { status: "invalid_code", tries_left: 4 },
  );
});

Deno.test("verify: new users are told to complete their profile", async () => {
  const w = new FakeWorld();
  const result = await verifyOtp(w, { phone: "015 999 888", token: GOOD_CODE });
  assertEquals(result.status === "signed_in" && result.is_new_user, true);
});

Deno.test("verify: blocked accounts get no session", async () => {
  const w = new FakeWorld();
  w.blockedUsers.add("u-vannak");
  // Blocked after the code was sent.
  assertEquals(await verifyOtp(w, { phone: "12345680", token: GOOD_CODE }), { status: "blocked" });
  assertEquals(w.signedOut, ["at-u-vannak"]);
});

Deno.test("verify: rejects malformed input", async () => {
  const w = new FakeWorld();
  await assertRejects(() => verifyOtp(w, { phone: "12345678", token: "12" }), BadRequest);
  await assertRejects(() => verifyOtp(w, { phone: "999", token: GOOD_CODE }), BadRequest);
  await assertRejects(() => verifyOtp(w, { phone: "12345678" }), BadRequest);
});

Deno.test("password: same 5 / 15 rule, keyed by email", async () => {
  const w = new FakeWorld();
  assertEquals(
    await passwordSignIn(w, { email: "Dara@kstore.example", password: "nope" }),
    { status: "invalid_credentials", tries_left: 4 },
  );
  for (let i = 0; i < 3; i++) {
    await passwordSignIn(w, { email: "dara@kstore.example", password: "x" });
  }
  assertEquals(
    (await passwordSignIn(w, { email: "dara@kstore.example", password: "x" })).status,
    "locked",
  );
  assertEquals(
    (await passwordSignIn(w, { email: "dara@kstore.example", password: GOOD_PASSWORD })).status,
    "locked",
  );
  // The phone counter is untouched.
  assertEquals((await sendOtp(w, { phone: "12345678" })).status, "sent");
});

Deno.test("handler: 400 for bad bodies, 200 with status otherwise", async () => {
  const w = new FakeWorld();
  const serve = handler(sendOtp, () => w);
  const post = (body: string) => serve(new Request("http://x", { method: "POST", body }));

  assertEquals((await post("not json")).status, 400);
  assertEquals((await post("[]")).status, 400);
  const bad = await post(JSON.stringify({ phone: "1" }));
  assertEquals(bad.status, 400);
  assertEquals((await bad.json()).error, "bad_request");

  const ok = await post(JSON.stringify({ phone: "12345678" }));
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).status, "sent");
  assertEquals((await serve(new Request("http://x", { method: "OPTIONS" }))).status, 200);
});

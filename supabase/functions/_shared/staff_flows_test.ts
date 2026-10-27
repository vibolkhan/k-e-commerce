import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import { BadRequest, Unauthorized } from "./errors.ts";
import {
  type Account,
  type Contact,
  formatInviteDate,
  manageStaff,
  parseContact,
  type StaffDeps,
  type StaffMember,
  type StaffRole,
} from "./staff_flows.ts";

const NOW = new Date("2026-10-27T03:00:00Z"); // 10:00 in Phnom Penh

// In-memory twin of auth + staff_members, keyed by access token.
class FakeWorld implements StaffDeps {
  appUrl = "https://admin.k.example/";
  tokens = new Map([["t-chenda", "u-chenda"], ["t-dalin", "u-dalin"], ["t-rachana", "u-rachana"]]);
  members = new Map<string, StaffMember>([
    ["u-chenda", member("u-chenda", "Chenda Lim", "super_admin", "active", "chenda@k.example")],
    ["u-dalin", member("u-dalin", "Dalin Chhay", "sales", "active", "dalin@k.example")],
    ["u-rachana", member("u-rachana", "Rachana Ty", "support", "invited", null, "+85592115408")],
  ]);
  accounts = new Map<string, Account>([
    ["dara@k.example", { profile_id: "u-dara", role: "customer", staff_status: null }],
    ["dalin@k.example", { profile_id: "u-dalin", role: "staff", staff_status: "active" }],
    ["+85512000111", { profile_id: "u-old", role: "staff", staff_status: "removed" }],
  ]);
  created: { contact: Contact; fullName: string }[] = [];
  emails: { email: string; isNewUser: boolean }[] = [];
  sms: { phone: string; body: string }[] = [];
  saved: { profileId: string; role: StaffRole; expiresAt: Date }[] = [];
  roles: { profileId: string; role: StaffRole }[] = [];
  removed: string[] = [];
  failSend = false;

  now = () => NOW;
  userIdFor(authorization: string | null) {
    const token = authorization?.replace(/^Bearer\s+/i, "") ?? "";
    return Promise.resolve(this.tokens.get(token) ?? null);
  }
  member(profileId: string) {
    return Promise.resolve(this.members.get(profileId) ?? null);
  }
  accountFor(contact: Contact) {
    const key = contact.kind === "email" ? contact.email : contact.phone;
    return Promise.resolve(this.accounts.get(key) ?? null);
  }
  activeSuperAdmins() {
    return Promise.resolve(
      [...this.members.values()].filter((m) =>
        m.staff_role === "super_admin" && m.status === "active"
      ).length,
    );
  }
  createUser(contact: Contact, fullName: string) {
    this.created.push({ contact, fullName });
    return Promise.resolve(`u-new-${this.created.length}`);
  }
  sendEmailInvite(email: string, isNewUser: boolean) {
    if (this.failSend) return Promise.reject(new Error("smtp down"));
    this.emails.push({ email, isNewUser });
    return Promise.resolve();
  }
  sendSms(phone: string, body: string) {
    if (this.failSend) return Promise.reject(new Error("twilio down"));
    this.sms.push({ phone, body });
    return Promise.resolve();
  }
  saveInvite(invite: { profileId: string; role: StaffRole; expiresAt: Date }) {
    this.saved.push(invite);
    return Promise.resolve();
  }
  setRole(profileId: string, role: StaffRole) {
    this.roles.push({ profileId, role });
    return Promise.resolve();
  }
  remove(profileId: string) {
    this.removed.push(profileId);
    return Promise.resolve();
  }
}

function member(
  id: string,
  name: string,
  role: StaffRole,
  status: StaffMember["status"],
  email: string | null,
  phone: string | null = null,
): StaffMember {
  return { profile_id: id, full_name: name, email, phone, staff_role: role, status };
}

const as = (token: string | null) =>
  new Request("http://x", {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });

const run = (world: FakeWorld, body: Record<string, unknown>, token: string | null = "t-chenda") =>
  manageStaff(world, body, as(token));

Deno.test("no session is 401", async () => {
  await assertRejects(() => run(new FakeWorld(), { action: "invite" }, null), Unauthorized);
});

Deno.test("only an active super admin manages staff", async () => {
  const world = new FakeWorld();
  assertEquals(await run(world, { action: "remove", profile_id: "u-chenda" }, "t-dalin"), {
    status: "forbidden",
  });
  assertEquals(await run(world, { action: "invite" }, "t-rachana"), { status: "forbidden" });
});

Deno.test("an unknown action is a bad request", async () => {
  await assertRejects(() => run(new FakeWorld(), { action: "promote" }), BadRequest);
});

Deno.test("invite by email creates the user and sends Auth's invite", async () => {
  const world = new FakeWorld();
  const result = await run(world, {
    action: "invite",
    full_name: " Sokim Ou ",
    contact: "Sokim@K.example",
    role: "catalog",
  });
  assertEquals(result, {
    status: "invited",
    profile_id: "u-new-1",
    expires_at: "2026-11-03T03:00:00.000Z",
  });
  assertEquals(world.created, [{
    contact: { kind: "email", email: "sokim@k.example" },
    fullName: "Sokim Ou",
  }]);
  assertEquals(world.emails, [{ email: "sokim@k.example", isNewUser: true }]);
  assertEquals(world.saved[0].role, "catalog");
});

Deno.test("invite by phone sends the invite SMS", async () => {
  const world = new FakeWorld();
  const result = await run(world, {
    action: "invite",
    full_name: "Rotha Kim",
    contact: "012 345 678",
    role: "support",
  });
  assertEquals(result.status, "invited");
  assertEquals(world.sms.length, 1);
  assertEquals(world.sms[0].phone, "+85512345678");
  assertStringIncludes(world.sms[0].body, "Chenda Lim invited you to the K back-office as Support");
  assertStringIncludes(world.sms[0].body, "https://admin.k.example/sign-in");
  assertStringIncludes(world.sms[0].body, "expires on 3 Nov 2026");
});

Deno.test("invite validates name, contact and role", async () => {
  const world = new FakeWorld();
  const base = { action: "invite", full_name: "A", contact: "a@k.example", role: "sales" };
  assertEquals(await run(world, { ...base, full_name: "  " }), {
    status: "invalid",
    field: "full_name",
  });
  assertEquals(await run(world, { ...base, contact: "12" }), {
    status: "invalid",
    field: "contact",
  });
  assertEquals(await run(world, { ...base, contact: "a@b" }), {
    status: "invalid",
    field: "contact",
  });
  assertEquals(await run(world, { ...base, role: "owner" }), { status: "invalid", field: "role" });
  assertEquals(world.created.length, 0);
});

Deno.test("invite refuses existing customers and current staff", async () => {
  const world = new FakeWorld();
  const base = { action: "invite", full_name: "X", role: "sales" };
  assertEquals(await run(world, { ...base, contact: "dara@k.example" }), {
    status: "account_exists",
  });
  assertEquals(await run(world, { ...base, contact: "dalin@k.example" }), {
    status: "already_staff",
  });
  assertEquals(world.saved.length, 0);
});

Deno.test("removed staff can be invited again", async () => {
  const world = new FakeWorld();
  const result = await run(world, {
    action: "invite",
    full_name: "Old Hand",
    contact: "+855 12 000 111",
    role: "sales",
  });
  assertEquals(result.status, "invited");
  assertEquals(world.created.length, 0);
  assertEquals(world.saved[0].profileId, "u-old");
});

Deno.test("a failed delivery says send_failed", async () => {
  const world = new FakeWorld();
  world.failSend = true;
  assertEquals(
    await run(world, { action: "invite", full_name: "A", contact: "a@k.example", role: "sales" }),
    { status: "send_failed" },
  );
});

Deno.test("resend renews a pending invite", async () => {
  const world = new FakeWorld();
  assertEquals(await run(world, { action: "resend", profile_id: "u-rachana" }), {
    status: "resent",
    expires_at: "2026-11-03T03:00:00.000Z",
  });
  assertEquals(world.sms[0].phone, "+85592115408");
  assertEquals(await run(world, { action: "resend", profile_id: "u-dalin" }), {
    status: "not_invited",
  });
  assertEquals(await run(world, { action: "resend", profile_id: "u-ghost" }), {
    status: "not_found",
  });
});

Deno.test("update_role changes another member's role", async () => {
  const world = new FakeWorld();
  assertEquals(
    await run(world, { action: "update_role", profile_id: "u-dalin", role: "support" }),
    {
      status: "updated",
    },
  );
  assertEquals(world.roles, [{ profileId: "u-dalin", role: "support" }]);
  assertEquals(await run(world, { action: "update_role", profile_id: "u-dalin", role: "x" }), {
    status: "invalid",
    field: "role",
  });
});

Deno.test("nobody edits or removes themselves", async () => {
  const world = new FakeWorld();
  assertEquals(await run(world, { action: "update_role", profile_id: "u-chenda", role: "sales" }), {
    status: "self",
  });
  assertEquals(await run(world, { action: "remove", profile_id: "u-chenda" }), { status: "self" });
});

Deno.test("a second super admin can be demoted or removed", async () => {
  const world = new FakeWorld();
  world.members.set("u-sok", member("u-sok", "Sok", "super_admin", "active", "sok@k.example"));
  assertEquals(await run(world, { action: "update_role", profile_id: "u-sok", role: "sales" }), {
    status: "updated",
  });
  assertEquals(await run(world, { action: "remove", profile_id: "u-sok" }), { status: "removed" });
});

Deno.test("demoting or removing the only other active super admin is refused", async () => {
  const world = new FakeWorld();
  // Chenda's own access is gone mid-session; Sok is the only active one left.
  world.members.set("u-sok", member("u-sok", "Sok", "super_admin", "active", null));
  world.activeSuperAdmins = () => Promise.resolve(1);
  assertEquals(await run(world, { action: "update_role", profile_id: "u-sok", role: "sales" }), {
    status: "last_super_admin",
  });
  assertEquals(await run(world, { action: "remove", profile_id: "u-sok" }), {
    status: "last_super_admin",
  });
  // Keeping them a super admin is fine.
  assertEquals(
    await run(world, { action: "update_role", profile_id: "u-sok", role: "super_admin" }),
    { status: "updated" },
  );
  assertEquals(world.removed.length, 0);
});

Deno.test("parseContact and formatInviteDate", () => {
  assertEquals(parseContact("+855 92 115 408"), { kind: "phone", phone: "+85592115408" });
  assertEquals(parseContact(" Visal@KStore.example "), {
    kind: "email",
    email: "visal@kstore.example",
  });
  assertEquals(parseContact("hello"), null);
  // 23:30 UTC is already the next day in Phnom Penh.
  assertEquals(formatInviteDate(new Date("2026-10-20T23:30:00Z")), "21 Oct 2026");
});

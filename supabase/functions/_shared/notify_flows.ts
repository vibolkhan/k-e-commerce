// The notification pipeline (F07, NOT-01/02): notify(user_ids, type, data).
//
// One call, for each recipient:
//   1. writes the inbox row (S-07), copy in both languages so a language
//      switch re-renders it;
//   2. sends a push to each of their devices, in their language, unless they
//      turned that kind off on S-08d (payments, refunds, account security
//      and rider jobs are always sent);
//   3. forgets tokens FCM says are dead.
//
// Other Edge Functions import `notify` and pass their own deps; the HTTP
// endpoint (`notifyRequest`) is for the service role, plus a self-test for
// signed-in users when NOTIFY_SELF_TEST is on (dev and staging only).
//
// Every outcome is HTTP 200 with a `status`; a malformed body is 400 and a
// caller who may not send is 401.

import { BadRequest, Unauthorized } from "./errors.ts";
import {
  type Category,
  type Locale,
  NOTIFICATION_TYPES,
  type NotificationType,
  type PrefGroup,
  type Recipient,
  render,
  requiredKeys,
  TEST_TARGET_IDS,
  TEST_TARGET_NAMES,
} from "./notify_types.ts";

const MAX_RECIPIENTS = 500;
const MAX_TEST_DELAY_SECONDS = 15;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** S-08d switches; a missing key means the default below. */
export type NotificationPrefs = Partial<
  Record<Exclude<PrefGroup, null>, { push?: boolean; email?: boolean }>
>;

/** Review reminders start off (S-08d); everything else starts on. */
const PUSH_DEFAULTS: Record<Exclude<PrefGroup, null>, boolean> = {
  orders: true,
  quotes: true,
  chat: true,
  reviews: false,
};

export interface Profile extends Recipient {
  prefs: NotificationPrefs;
}

export interface NewNotification {
  profile_id: string;
  type: string;
  category: Category;
  title: Record<Locale, string>;
  body: Record<Locale, string>;
  payload: Record<string, unknown>;
}

export interface DeviceToken {
  profile_id: string;
  token: string;
  platform: "ios" | "android" | "web";
}

export interface PushMessage {
  token: string;
  platform: DeviceToken["platform"];
  title: string;
  body: string;
  /** All strings: FCM data values must be. */
  data: Record<string, string>;
  /** App-icon badge on iOS: the recipient's unread count. */
  badge: number;
  sound?: "job";
}

/** `invalid_token`: uninstalled or expired; the token is deleted. */
export type PushResult = "sent" | "invalid_token" | "failed";

export interface PushSender {
  send(message: PushMessage): Promise<PushResult>;
}

export interface NotifyDeps {
  /** Recipients that can still receive anything: not deleted, not blocked. */
  recipients(ids: string[]): Promise<Profile[]>;
  /** Inserts inbox rows; returns their ids in the same order. */
  insertNotifications(rows: NewNotification[]): Promise<string[]>;
  unreadCounts(ids: string[]): Promise<Map<string, number>>;
  tokens(ids: string[]): Promise<DeviceToken[]>;
  deleteTokens(tokens: string[]): Promise<void>;
  push: PushSender;
}

export interface NotifyResult {
  status: "sent";
  /** Inbox rows written. */
  inbox: number;
  /** Devices that accepted the push. */
  pushed: number;
  /** Recipients without a push: switched off, no device, or not found. */
  skipped: number;
}

export function wantsPush(type: NotificationType, prefs: NotificationPrefs): boolean {
  if (type.pref === null) return true;
  return prefs[type.pref]?.push ?? PUSH_DEFAULTS[type.pref];
}

function validate(typeName: unknown, data: unknown): {
  type: NotificationType;
  data: Record<string, unknown>;
} {
  if (typeof typeName !== "string" || !(typeName in NOTIFICATION_TYPES)) {
    throw new BadRequest(`unknown type ${typeName}`);
  }
  if (data !== undefined && (typeof data !== "object" || data === null || Array.isArray(data))) {
    throw new BadRequest("data must be an object");
  }
  const type = NOTIFICATION_TYPES[typeName];
  const values = (data ?? {}) as Record<string, unknown>;
  const missing = requiredKeys(type).filter((key) => values[key] == null);
  if (missing.length > 0) throw new BadRequest(`data is missing ${missing.join(", ")}`);
  const idKeys = [...(type.routeKeys ?? [])];
  if (typeName === "test") {
    const target = String(values.target ?? "inbox");
    if (!TEST_TARGET_NAMES.includes(target)) {
      throw new BadRequest(`target must be one of ${TEST_TARGET_NAMES.join(", ")}`);
    }
    const idKey = TEST_TARGET_IDS[target];
    if (idKey) idKeys.push(idKey);
  }
  // Ids end up in a path; nothing but a uuid may get there.
  for (const key of idKeys) {
    if (!UUID.test(String(values[key]))) throw new BadRequest(`${key} must be a uuid`);
  }
  return { type, data: values };
}

function copy(type: NotificationType, data: Record<string, unknown>) {
  try {
    return {
      title: { en: render(type.title.en, data, "en"), km: render(type.title.km, data, "km") },
      body: { en: render(type.body.en, data, "en"), km: render(type.body.km, data, "km") },
    };
  } catch (e) {
    throw new BadRequest(e instanceof Error ? e.message : String(e));
  }
}

/** Writes the inbox rows and sends the pushes. Throws BadRequest on bad input. */
export async function notify(
  deps: NotifyDeps,
  userIds: string[],
  typeName: string,
  data: Record<string, unknown> = {},
): Promise<NotifyResult> {
  const { type, data: values } = validate(typeName, data);
  const ids = [...new Set(userIds)];
  if (ids.length === 0 || ids.length > MAX_RECIPIENTS) {
    throw new BadRequest(`user_ids must hold 1 to ${MAX_RECIPIENTS} ids`);
  }
  if (!ids.every((id) => UUID.test(id))) throw new BadRequest("user_ids must be uuids");
  const text = copy(type, values);

  const people = await deps.recipients(ids);
  if (people.length === 0) return { status: "sent", inbox: 0, pushed: 0, skipped: ids.length };

  const rows: NewNotification[] = people.map((to) => ({
    profile_id: to.id,
    type: typeName,
    category: type.category,
    title: text.title,
    body: text.body,
    payload: { ...values, route: type.route(values, to) },
  }));
  const notificationIds = await deps.insertNotifications(rows);

  const pushTo = people.filter((to) => wantsPush(type, to.prefs));
  const [tokens, unread] = pushTo.length === 0
    ? [[], new Map<string, number>()]
    : await Promise.all([
      deps.tokens(pushTo.map((p) => p.id)),
      deps.unreadCounts(pushTo.map((p) => p.id)),
    ]);

  const byId = new Map(
    people.map((p, i) => [p.id, { person: p, row: rows[i], id: notificationIds[i] }]),
  );
  const results = await Promise.all(tokens.map(async (device) => {
    const { person, row, id } = byId.get(device.profile_id)!;
    const result = await deps.push.send({
      token: device.token,
      platform: device.platform,
      title: row.title[person.locale],
      body: row.body[person.locale],
      data: { type: typeName, route: String(row.payload.route), notification_id: id },
      badge: unread.get(person.id) ?? 0,
      sound: type.sound,
    });
    return { device, result };
  }));

  const dead = results.filter((r) => r.result === "invalid_token").map((r) => r.device.token);
  if (dead.length > 0) await deps.deleteTokens(dead);

  const reached = new Set(
    results.filter((r) => r.result === "sent").map((r) => r.device.profile_id),
  );
  return {
    status: "sent",
    inbox: rows.length,
    pushed: results.filter((r) => r.result === "sent").length,
    skipped: ids.length - reached.size,
  };
}

// ---------------------------------------------------------------- HTTP

export type Caller = { kind: "service" } | { kind: "user"; id: string };

export interface NotifyHttpDeps extends NotifyDeps {
  /** Service role key → service; a user session → that user; else null. */
  callerFor(authorization: string | null): Promise<Caller | null>;
  /** NOTIFY_SELF_TEST: signed-in users may send `test` to themselves. */
  selfTestEnabled: boolean;
  sleep(ms: number): Promise<void>;
}

/**
 * `{ user_ids, type, data? }` from the service role, or `{ type: "test",
 * data?: { target, order_id | rfq_id | conversation_id, delay_seconds } }`
 * from a signed-in user to themselves (self-test). A delay lets the tester
 * put the app in the background or close it first.
 */
export async function notifyRequest(
  deps: NotifyHttpDeps,
  body: Record<string, unknown>,
  req: Request,
): Promise<NotifyResult> {
  const caller = await deps.callerFor(req.headers.get("Authorization"));
  if (!caller) throw new Unauthorized();

  if (caller.kind === "service") {
    const userIds = body.user_ids;
    if (!Array.isArray(userIds) || !userIds.every((id) => typeof id === "string")) {
      throw new BadRequest("user_ids must be an array of ids");
    }
    return notify(deps, userIds, body.type as string, body.data as Record<string, unknown>);
  }

  if (!deps.selfTestEnabled || body.type !== "test") throw new Unauthorized();
  const data = (body.data ?? {}) as Record<string, unknown>;
  const delay = Number(data.delay_seconds ?? 0);
  if (!Number.isFinite(delay) || delay < 0 || delay > MAX_TEST_DELAY_SECONDS) {
    throw new BadRequest(`delay_seconds must be 0 to ${MAX_TEST_DELAY_SECONDS}`);
  }
  // Only the target and its id go through; the copy is fixed.
  const target = String(data.target ?? "inbox");
  const idKey = TEST_TARGET_IDS[target];
  const testData = { target, ...(idKey ? { [idKey]: data[idKey] } : {}) };
  // Validate before waiting, so a bad request fails at once.
  validate("test", testData);
  if (delay > 0) await deps.sleep(delay * 1000);
  return notify(deps, [caller.id], "test", testData);
}

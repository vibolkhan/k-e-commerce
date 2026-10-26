import { assertEquals } from "@std/assert";
import { fcmMessage, fcmSender, isDeadToken } from "./fcm.ts";
import type { PushMessage } from "./notify_flows.ts";

const msg: PushMessage = {
  token: "device-1",
  platform: "android",
  title: "Payment received",
  body: "We got $92.00 by KHQR for #K-10248.",
  data: { type: "payment_received", route: "/customer/orders/o-1", notification_id: "n-1" },
  badge: 3,
};

Deno.test("a message carries the route for every platform", () => {
  const m = fcmMessage(msg, "https://shop.example/") as Record<string, any>;
  assertEquals(m.token, "device-1");
  assertEquals(m.notification, { title: "Payment received", body: msg.body });
  assertEquals(m.data.route, "/customer/orders/o-1");
  assertEquals(m.android.notification.channel_id, "k_default");
  assertEquals(m.apns.payload.aps, { badge: 3, sound: "default" });
  assertEquals(m.webpush.fcm_options.link, "https://shop.example/#/customer/orders/o-1");
});

Deno.test("job alerts use the jobs channel; no web link without a web URL", () => {
  const m = fcmMessage({ ...msg, sound: "job" }) as Record<string, any>;
  assertEquals(m.android.notification.channel_id, "k_jobs");
  assertEquals(m.webpush, undefined);
});

Deno.test("only token errors count as dead tokens", () => {
  assertEquals(
    isDeadToken(404, { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] }),
    true,
  );
  assertEquals(isDeadToken(400, { status: "INVALID_ARGUMENT" }), true);
  assertEquals(
    isDeadToken(400, { status: "INVALID_ARGUMENT", details: [{ errorCode: "INVALID_ARGUMENT" }] }),
    false,
  );
  assertEquals(isDeadToken(503, { status: "UNAVAILABLE" }), false);
  assertEquals(isDeadToken(401, { status: "UNAUTHENTICATED" }), false);
});

Deno.test("signs in once, reuses the token, and maps FCM answers", async () => {
  const { privateKey } = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\\n${
    btoa(String.fromCharCode(...der))
  }\\n-----END PRIVATE KEY-----\\n`;

  const calls: string[] = [];
  const answers = [
    new Response("{}", { status: 200 }),
    Response.json({ error: { status: "NOT_FOUND", details: [{ errorCode: "UNREGISTERED" }] } }, {
      status: 404,
    }),
    Response.json({ error: { status: "UNAVAILABLE" } }, { status: 503 }),
  ];
  const fakeFetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push(url);
    if (url.includes("oauth2")) {
      const assertion = new URLSearchParams(String(init?.body)).get("assertion")!;
      assertEquals(assertion.split(".").length, 3);
      return Promise.resolve(Response.json({ access_token: "at-1", expires_in: 3600 }));
    }
    assertEquals((init?.headers as Record<string, string>).Authorization, "Bearer at-1");
    return Promise.resolve(answers.shift()!);
  };

  const sender = fcmSender(
    { projectId: "k-shop", clientEmail: "push@k-shop.iam.gserviceaccount.com", privateKey: pem },
    { fetch: fakeFetch as typeof fetch, now: () => 1_000_000 },
  );
  assertEquals(await sender.send(msg), "sent");
  assertEquals(await sender.send(msg), "invalid_token");
  assertEquals(await sender.send(msg), "failed");
  assertEquals(calls.filter((u) => u.includes("oauth2")).length, 1);
  assertEquals(calls[1], "https://fcm.googleapis.com/v1/projects/k-shop/messages:send");
});

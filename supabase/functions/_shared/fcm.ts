// Firebase Cloud Messaging (HTTP v1) behind `PushSender`, so another
// provider or a test double can stand in. iOS goes through APNs via FCM.
//
// Auth is a Google service account: a signed JWT is swapped for an OAuth
// token, cached until shortly before it expires.

import type { PushMessage, PushResult, PushSender } from "./notify_flows.ts";

export interface ServiceAccount {
  projectId: string;
  clientEmail: string;
  /** PEM, PKCS#8 ("-----BEGIN PRIVATE KEY-----"). */
  privateKey: string;
}

/** Android channels the app creates at start-up (MainActivity.kt). */
export const ANDROID_CHANNELS = { default: "k_default", job: "k_jobs" } as const;

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

/** The FCM v1 `message` for one device. [webBaseUrl] makes web taps open the route. */
export function fcmMessage(msg: PushMessage, webBaseUrl?: string): Record<string, unknown> {
  const job = msg.sound === "job";
  const message: Record<string, unknown> = {
    token: msg.token,
    notification: { title: msg.title, body: msg.body },
    data: msg.data,
    android: {
      priority: "high",
      notification: {
        channel_id: job ? ANDROID_CHANNELS.job : ANDROID_CHANNELS.default,
        default_sound: true,
        // Opens the Flutter activity; the app reads `data.route`.
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    apns: {
      headers: { "apns-priority": "10" },
      payload: { aps: { badge: msg.badge, sound: "default" } },
    },
  };
  if (webBaseUrl) {
    // The web app uses hash URLs: https://shop.example/#/customer/orders/<id>
    const link = `${webBaseUrl.replace(/\/+$/, "")}/#${msg.data.route}`;
    message.webpush = { fcm_options: { link } };
  }
  return message;
}

/** FCM error → whether the token itself is dead (uninstalled, expired, foreign). */
export function isDeadToken(status: number, error: unknown): boolean {
  const e = error as { status?: string; details?: { errorCode?: string }[] } | undefined;
  const codes = (e?.details ?? []).map((d) => d.errorCode);
  if (codes.includes("UNREGISTERED") || codes.includes("SENDER_ID_MISMATCH")) return true;
  if (status === 404 || e?.status === "NOT_FOUND") return true;
  // A malformed token is INVALID_ARGUMENT with no other detail.
  return status === 400 && e?.status === "INVALID_ARGUMENT" && codes.length === 0;
}

function base64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const b of raw) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signedJwt(account: ServiceAccount, nowSeconds: number): Promise<string> {
  const pem = account.privateKey.replace(/\\n/g, "\n");
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.clientEmail,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const input = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(input),
  );
  return `${input}.${base64url(new Uint8Array(signature))}`;
}

export function fcmSender(
  account: ServiceAccount,
  options: { webBaseUrl?: string; fetch?: typeof fetch; now?: () => number } = {},
): PushSender {
  const http = options.fetch ?? fetch;
  const now = options.now ?? Date.now;
  let cached: { token: string; expiresAt: number } | null = null;

  async function accessToken(): Promise<string> {
    if (cached && cached.expiresAt - 60_000 > now()) return cached.token;
    const assertion = await signedJwt(account, Math.floor(now() / 1000));
    const res = await http(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });
    if (!res.ok) throw new Error(`FCM auth failed: ${res.status} ${await res.text()}`);
    const { access_token, expires_in } = await res.json();
    cached = { token: access_token, expiresAt: now() + expires_in * 1000 };
    return access_token;
  }

  return {
    async send(msg: PushMessage): Promise<PushResult> {
      try {
        const res = await http(
          `https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${await accessToken()}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ message: fcmMessage(msg, options.webBaseUrl) }),
          },
        );
        if (res.ok) {
          await res.body?.cancel();
          return "sent";
        }
        const { error } = await res.json().catch(() => ({ error: undefined }));
        if (isDeadToken(res.status, error)) return "invalid_token";
        console.error("FCM send failed", res.status, JSON.stringify(error));
        return "failed";
      } catch (e) {
        // One device failing must not fail the inbox write or other devices.
        console.error("FCM send failed", e);
        return "failed";
      }
    },
  };
}

/** No Firebase project configured yet: the inbox still works, pushes are logged. */
export const noopSender: PushSender = {
  send(msg) {
    console.log(`push skipped (FCM not configured): ${msg.data.type} → ${msg.data.route}`);
    return Promise.resolve("failed");
  },
};

# F07 — Push notifications & inbox

F07 adds one notification pipeline that every later feature can call: `notify(user_ids, type, data)` writes the inbox row and sends a push that opens the right screen.
- Requirements: NOT-01, NOT-02, App Flow F10 and §6 (notification matrix).
- Screens: S-07, S-08d, N-01, N-02, N-03 / N-03a.

## The pipeline

```
other Edge Function ──import──▶ notify(deps, user_ids, type, data)     _shared/notify_flows.ts
service role (curl) ──HTTP────▶ /functions/v1/notify
signed-in user ─────HTTP──────▶   (type "test", to themselves; dev only)
                                   │
                1. validate type + data (unknown type, missing keys, non-uuid ids → 400)
                2. recipients: skip deleted and blocked profiles
                3. insert one notifications row per person: copy in en + km, category, payload.route
                4. push unless S-08d turned that kind off (always-on kinds ignore the switches)
                   → FCM HTTP v1, in the person's profiles.locale, data {route, type, notification_id},
                     iOS badge = unread count, Android channel k_default / k_jobs, web link /#/<route>
                5. delete tokens FCM reports as dead (UNREGISTERED, malformed)
                → { status: "sent", inbox, pushed, skipped }
```

- **The inbox always gets the row.** The S-08d switches control push (and later email) only.
- **Copy is rendered on the server** from the registry in `_shared/notify_types.ts`, using the N-01/N-02 wording. Callers pass data, not text.
- **Placeholders:** `{key}` is plain text, `{amount:money}` turns cents into `$2,260.50`, `{x:date}` gives `5 Nov`, `{x:day}` gives `Sun 25 Oct`, and `{x:time}` gives `2:01 PM`. All dates and times are in Phnom Penh time.
- **Without FCM secrets, every push is logged and skipped.** The inbox and the in-app banner still work.

### Calling it from a later feature

```ts
import { notify } from "../_shared/notify_flows.ts";
import { notifyDeps } from "../_shared/notify_deps.ts";

await notify(notifyDeps(), [order.profile_id], "payment_received", {
  order_id: order.id, order_number: order.number, amount: order.total_cents,
});
```

To add an event, add an entry to `NOTIFICATION_TYPES`. A test checks that every type has both languages with the same placeholders.

### Types, tabs and links

| Type(s) | S-07 tab | S-08d switch | Opens |
|---|---|---|---|
| `order_confirmed_cod`, `order_packing`, `order_out_for_delivery`, `order_delivered`, `delivery_failed`, `return_approved`, `return_rejected` | Orders | Orders & delivery | `<shell>/orders/<order_id>` (C-12) |
| `payment_received`, `payment_expired`, `bank_transfer_confirmed`, `bank_slip_rejected`, `refund_sent` | Orders | **always sent** | `<shell>/orders/<order_id>` |
| `review_reminder` | Orders | Review reminders (**off by default**) | `<shell>/orders/<order_id>` |
| `quote_ready`, `quote_revised`, `quote_expiring` | Quotes | Quotes | `/business/quotes/<rfq_id>` (B-05) |
| `chat_message` | Chat | Chat messages | `<shell>/chat/<conversation_id>` (C-17) |
| `business_approved`, `business_rejected` | All only | **always sent** | `<shell>/account` |
| `job_assigned`, `return_pickup_assigned` (sound), `job_reassigned` | — | always sent | `/rider` until R-01 |
| `admin_*` (new order, RFQ, bank slip, return, verification, low stock, delivery failed, chat waiting) | — | always sent | `/admin` until A-01 |
| `test` | All only | always sent | `data.target`: `inbox`, `order`, `quote` or `chat` |

`<shell>` is `/business` for business buyers and `/customer` for everyone else, so a single order event links each person into their own app.

## Database (`supabase/migrations/20261029000100_notifications.sql`)

The `notifications`, `device_tokens` and `profiles.notification_prefs` tables came with F04. F07 adds:
- **`notifications.category`** (`orders` / `quotes` / `chat` / `account`) with an unread index. `id` and `category` are now server-only; users can still change only `read_at`.
- **`mark_all_notifications_read(p_category?)`** runs as the caller under RLS and returns how many rows it changed.
- **`register_device_token(token, platform)`** is security definer. It upserts on `token`, so a phone that another person signs in on moves to them. The client can't do this itself because RLS hides the previous owner's row. Sign-out deletes the row through the existing RLS policy.
- **One shape for `notification_prefs`:** `{"orders": {"push", "email"}, "quotes": {"push", "email"}, "chat": {"push"}, "reviews": {"push"}}`, where a missing key means the default. F05's `email_receipts` became `orders.email`, and S-06 now writes that.
- Account deletion (F06) already removes notifications and tokens.

## App (`lib/features/notifications/`)

| Piece | What it does |
|---|---|
| S-07 `inbox_page.dart` | Tabs All (unread count) / Orders / Quotes / Chat. Rows are grouped Today / Earlier in Phnom Penh time. Unread rows have a bold title, darker body and blue dot. Times read `1:50 PM`, then `Yesterday`, then `21 Oct`. A tap marks the row read and opens its route. Mark all read sits in the header. The empty state reads "You're all caught up". Updates live through Realtime (latest 100 rows). |
| Bell `notification_bell.dart` | Sits on the S-08 header and the customer/business home placeholder. Red dot while anything is unread; label "Notifications, 3 unread". Signed-in users only. |
| S-08d `notification_settings_page.dart` | Orders & delivery (Push, Email), Quotes (Push, Email; business buyers only), Chat (Push), Review reminders (Push, off). The whole row toggles. A change saves at once and flips back with a toast if saving fails. Banner: "Payment and security messages are always sent." Dev and staging builds add a **Test push** card. |
| N-03a `in_app_banner.dart` | A new row arriving while the app is open slides in at the top for 5 s. It has a tonal action ("Track" for a delivery on its way, otherwise "View"), can be swiped up to dismiss, and is a live region for screen readers. It is driven by the live inbox, so it works without push and never doubles with FCM. It is not shown on the inbox itself, or for rows older than 2 minutes, such as after a reconnect. |
| `PushController` | On sign-in it asks for permission and registers the token, re-registering when FCM rotates it. A tapped push marks its row read and calls `router.go(route)`. A push that launched the app waits for launch via `?from=`. On sign-out it removes the token first, while the session can still delete it. |
| Placeholders | `/customer/orders/:id`, `/business/orders/:id`, `/<shell>/chat/:id` and `/business/quotes/:id` show "This screen (C-12) arrives in a later update." with the id. The paths are final; C-12, B-05 and C-17 replace the page only. Back goes to home when the page was opened from a push. |

Only in-app paths (`/…`, never `//host`) from a push or row reach the router (`safeRoute`). The server only puts uuids into paths.

### Platforms

| | Setup in the repo |
|---|---|
| Android | `POST_NOTIFICATIONS` permission (Android 13+). Channels `k_default` ("Notifications") and `k_jobs` ("New delivery jobs") are created in `MainActivity.kt`, in English and Khmer. Default channel meta-data is set. |
| iOS | `Runner.entitlements` with `aps-environment`, `UIBackgroundModes: remote-notification`, and a **minimum of iOS 15** (FlutterFire 17). The app-icon badge (the unread count from the push) clears when the app opens. FCM shows nothing in the foreground; the in-app banner does. |
| Web | `web/firebase-messaging-sw.js` shows background pushes, and a tap opens `<APP_WEB_URL>/#/<route>`. Its config lives in `web/firebase-config.js`, which is gitignored and written by `dart run tool/web_push_config.dart`. Without that file, web push is off. |

Firebase starts only when the build has the `FIREBASE_*` keys for its platform (`lib/core/config/firebase_config.dart`). If they are missing or wrong, the app runs without push.

## Setup the project owner must do

> **Status (2026-10-27): skipped for now.** The team decided to go ahead without Firebase. The steps below are on hold, and the app runs without push until they are done.

1. **Create a Firebase project** (K, with Analytics off) and add three apps:
   - Android `com.example.k_e_commerce`
   - iOS `com.example.kECommerce`
   - Web

   Change the bundle ids first if the placeholder ids are being replaced; they are still the template TODO.
2. **Copy the keys into `config/env.json`** (see `config/env.example.json`). They come from Project settings › General › each app:
   - `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`
   - `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_API_KEY`
   - `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY`
   - `FIREBASE_WEB_APP_ID`, `FIREBASE_WEB_API_KEY`
   - `FIREBASE_WEB_VAPID_KEY`, from Cloud Messaging › Web Push certificates
3. **iOS / APNs:**
   1. In the Apple Developer portal, turn on Push Notifications for the app id.
   2. Create an APNs auth key (.p8) and upload it in Firebase › Cloud Messaging › Apple app configuration.
   3. Use a paid team for signing; personal teams can't sign push.
4. **Server secrets:** create a service-account key with the "Firebase Cloud Messaging API Admin" role. Copy `supabase/functions/.env.example` to `.env`, fill in `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` and `APP_WEB_URL`, then run `supabase secrets set --env-file supabase/functions/.env`. Set `NOTIFY_SELF_TEST=true` on dev and staging only.
5. **Web:** run `dart run tool/web_push_config.dart` before `flutter run -d chrome` or `flutter build web`, and add that step to the web deploy job.
6. **Deploy:** `supabase db push`, then `supabase functions deploy notify`.

## Testing it

```
flutter analyze && flutter test --exclude-tags golden   # 217 tests (36 new)
supabase test db                                         # 226 pgTAP tests incl. 10_notifications
cd supabase/functions && deno test _shared/              # 38 tests (20 new: notify_flows, fcm)
```

- **`_shared/notify_flows_test.ts`:**
  - inbox row plus push to every device, in the reader's language (Khmer included);
  - order links into the recipient's own shell;
  - a switched-off kind still reaches the inbox, payments bypass the switches, and review reminders start off;
  - dead tokens are pruned;
  - deleted or blocked people are skipped;
  - the rider job sound;
  - bad input is refused before anything is written;
  - service role vs self-test, test targets and delay;
  - HTTP 401 / 400 / 200;
  - money, date and time formatting;
  - both languages carry the same placeholders for every type.
- **`_shared/fcm_test.ts`:**
  - message shape per platform (channel, badge, web link);
  - dead-token detection;
  - the OAuth token is fetched once and reused;
  - FCM answers map to sent / invalid_token / failed (with a real RSA-signed JWT).
- **`10_notifications.test.sql`:**
  - users can't insert notifications or move them between tabs;
  - mark all read per tab and in total, own rows only;
  - visitors are refused;
  - registering is idempotent, and a token moves to the next user on the device;
  - delete on sign-out;
  - unknown platforms are refused;
  - prefs must be an object.
- **`test/features/notifications/notifications_test.dart`** (full app with fakes):
  - bell dot and label;
  - S-07 groups, dots, bold titles, times and tab filtering;
  - tap → placeholder → back;
  - mark all read, and its failure;
  - empty state; Khmer;
  - guests have no inbox; customers can't open a quote link;
  - S-08d per role, saving, and rollback on failure;
  - dev test push;
  - N-03a: shown, Track, 5 s, swipe away, action opens and marks read, not for old rows or on the inbox;
  - push: register and rotate on sign-in, no prompt for guests, tap opens and marks read, launch tap after splash, business quote link, sign-out removes the token.
- **`notifications_domain_test.dart`:** row parsing, tab mapping, `safeRoute`, prefs defaults and merging, Phnom Penh time labels and the Today/Earlier split.
- **Builds:** `flutter build web`, `flutter build ios --no-codesign` and `flutter build apk --debug` all pass.

Against the local stack (`supabase start`, `supabase functions serve --env-file supabase/functions/.env` with `NOTIFY_SELF_TEST=true`):

```sh
SR=$(supabase status -o json | jq -r .SERVICE_ROLE_KEY)
curl -X POST http://127.0.0.1:54321/functions/v1/notify -H "Authorization: Bearer $SR" \
  -H 'Content-Type: application/json' \
  -d '{"user_ids":["a0000000-0000-4000-8000-000000000021"],"type":"payment_received",
       "data":{"order_id":"d0000000-0000-4000-8000-000000010250","order_number":"K-10250","amount":2550}}'
```

- **Results** (`push` stays 0 until FCM secrets exist):
  - The service role returned `{"status":"sent","inbox":1,"pushed":0,"skipped":1}`. The row was in both languages with `route /customer/orders/…`.
  - No session returned 401.
  - Dara sending to Sokha returned 401.
  - Dara's self-test landed in her own inbox.
  - With Dara's Orders push off, `order_packing` was written to the inbox and not pushed.
  - The app's REST calls worked as Dara: register token, inbox select, mark all read for chat (1 row), prefs update.
- **Seed:** `seed.sql` now gives Dara the S-07 inbox (3 unread) and Sokha a "quote ready". Run `supabase db reset` to restore it after manual tests.

### "Done when": test push on every platform (needs the owner setup above)

1. Sign in on the device as `dara@kstore.example` (or `sokha@kstore.example` for a quote) and allow notifications.
2. Account › Notifications › **Test push**: pick a target (Inbox, Order K-10248, Support chat, or Quote RFQ-0312 for business), then tap Send. The push arrives after 10 s:
   - background or close the app → the system push; tapping it opens the target (cold start too);
   - keep the app open → the N-03a banner; its action opens the target.
3. The test is in S-07 under All either way.

This step is **not yet done**: it needs the Firebase project, the APNs key and the FCM secrets.

## Decisions and assumptions

- **Built without Firebase keys** (agreed). Everything runs and is tested without them, and the last check above waits for the owner setup.
- **Order, quote and chat links use their final paths with placeholder pages** (agreed). C-12, B-05 and C-17 swap in the real screen.
- **Always sent:** payments (received, expired, bank transfer confirmed/rejected), refunds, business-account decisions, rider jobs and staff alerts. "Security" messages have no event yet; new-device or password alerts would go in this group.
- **The inbox always gets the row;** switches control push and email. Email itself is F34; the Email switches are stored now so F34 only reads them.
- Returns and review reminders file under the **Orders** tab (S-07 has no Returns tab). Business-account and test notifications show under All only.
- **Push permission is asked right after sign-in.** The design has no pre-permission screen, and guests are never asked.
- **The N-03a banner comes from the live inbox, not from FCM foreground messages,** so it works on every platform, with or without push, and never shows twice.
- **iOS app badge:** the push sets it to the unread count, and it clears when the app opens; the bell dot then shows unread.
- **FCM registration tokens, not FlutterFire 17's new installation-ID API.** The server sends with HTTP v1 `message.token`. The deprecated calls are marked with `ignore_for_file` in `push_service.dart`.
- **`notify` keeps the gateway JWT check off and checks the caller itself.** Only the exact service-role key may notify others; a user session may only self-test, and only when `NOTIFY_SELF_TEST=true`.
- The KHQR-expired push opens the order (C-12) for now. N-01 says C-09; F18 can point it there.
- **Design deviations:**
  - The review reminder title reads "How was your order?" because callers send a product name, not a noun like "sneakers".
  - "Return not approved" and "Transfer slip rejected" use generic bodies; the design's text names one specific reason.
  - The rider and admin types open their role's home until their screens exist.
  - S-08d's dev-only Test push card is not in the design and is hidden in prod.
  - The bell on the rider and admin homes comes with F21/F37.
- Golden tests are Windows-generated and differ on macOS. They fail locally as before, and CI excludes them; F07 adds none.

## Follow-ups

- Owner setup above, then the on-device check on Android, iOS and Chrome.
- F35 wires each matrix event to `notify()` from the function or trigger that causes it, and adds de-duplication. F18, F25, F27–F30, F32 and F33 call it as they land.
- Move to FCM installation IDs (`register` / `onRegistered`) once the server sends to them.
- The inbox keeps the latest 100 rows live. Paging older rows and an exact server-side unread count can come with the admin panel (A-01a, F37).
- C-09 for the KHQR-expired push (F18), and R-01/A-xx deep links for rider and admin pushes (F21, F37).
- Native Khmer review of the new strings (`notif*`, `placeholder*`, the server templates in `notify_types.ts`, Android channel names).
- Replace the template bundle ids (`com.example.*`) before registering the Firebase apps.

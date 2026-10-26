# F06 — Launch, role routing & account area

The app opens the right home for each role, and customers and business buyers get a complete Account area, including account deletion.
- Requirements: App Flow F0, AUTH-07.
- Screens: S-01, S-02, S-03a–c, S-08, S-08a, S-08b, S-08c, S-08e, S-08f, S-08g.

## Launch (App Flow F0)

| Step | Screen | Rule |
|---|---|---|
| Open the app | S-01 | K mark on brand sky. Shown until the saved session **and** its profile have loaded, so nobody is routed with a guessed role. |
| First launch | S-02 | Picking a card switches the language at once. Continue saves the language shown, even if the person kept the preselected one. |
| First launch | S-03a–c | Three slides: shop, pay with KHQR/COD, same-day delivery. Next / Skip / Start shopping. Riders and staff skip them. |
| Done | — | A session goes to that role's home; no session goes to Customer Home as a guest. A link that opened the app (web reload, deep link) is carried through every step as `?from=` and opened at the end; only in-app paths are accepted. |

Progress is saved on the device (`OnboardingStore`, SharedPreferences keys `onboarding.language` and `onboarding.intro`). The rules live in one pure function, `launchRedirect` in `lib/core/router/app_router.dart`, next to `roleRedirect` and `accountRedirect`.

## Role routing

| Role (DB `user_role`) | Home | Shell |
|---|---|---|
| guest, `customer` | `/customer` | Home + Account tabs |
| `business` | `/business` | Home + Account tabs |
| `rider` | `/rider` | placeholder home (language, sign out) |
| `staff` (any staff role) | `/admin` | placeholder home (language, sign out) |

- No role can open another role's paths, including `/<shell>/account/...`. Those show "No access".
- A role change (sign-in, sign-out) opens the new role's home unless the person is already inside it. For example, a rider signing in from the customer Account tab lands on Rider Home.
- `account/edit` and `account/delete` send guests back to the Account tab.
- Categories, cart / quote list and orders join the bottom bar as their tasks land.

## Account area

| Screen | What it does |
|---|---|
| S-08 | Initials, name and phone, Edit. "Become a business buyer" for customers only. My activity: Orders, Wishlist, Returns, Addresses. Settings: Language, Notifications, Help & support, Terms & privacy, Sign out. Delete account link. |
| S-08a | Guest: sign-in card (Sign in / Create an account both open S-04 and return here), Language, Help, Terms. |
| S-08b | Full name (required), email (optional, validated). The phone is shown read-only as "Verified". Saves through RLS (`profiles: update own`). |
| S-08c | The existing language sheet (F03). |
| S-08e | "Sign out?" confirmation. Also used by the rider and admin placeholder homes. |
| S-08f | What is deleted and what is kept, an optional reason (sent as a code, e.g. `not_using`), and an "I understand" tick. The danger button stays disabled until the box is ticked. |
| S-08g | "Delete your account?" with Keep account / Delete. On success the app signs out locally and lands on guest Customer Home. |

Rows whose screens belong to later tasks (orders, wishlist, returns, addresses, notifications settings, help, terms, business upgrade) show a "Coming in a later update." toast.

## Account deletion (AUTH-07)

```
supabase/
  migrations/20261028000100_account_deletion.sql
    profiles.deleted_at; profiles no longer cascade from auth.users (tombstone)
    phone / deleted_at / deletion_requested_at: server-only columns
    account_deletion_check(uid)          service role → {role, active_orders, open_returns}
    private.anonymise_account(uid, reason)
    trigger before delete on auth.users  → anonymise_account (reason from app_metadata)
  functions/
    _shared/account_flows.ts             the rules (pure, unit-tested)
    _shared/account_deps.ts              service-role wiring (JWT → user, Storage, Auth admin)
    account-delete/                      { reason? } + user JWT → deleted | has_active_orders | not_allowed
  tests/database/09_account_deletion.test.sql
```

`account-delete` keeps the gateway JWT check on. Its steps:
1. Read the caller from the JWT.
2. Refuse riders and staff (`not_allowed`): an admin removes those accounts.
3. Refuse if there is an unfinished order (`pending_payment` … `out_for_delivery`, `failed_delivery`) or return (`requested` … `inspected`). The answer is `has_active_orders`, and the app shows why.
4. Remove the user's files under `<uid>/` in `business-docs` and `chat-attachments`.
5. Store the reason in app metadata and delete the auth user.

Deleting the auth user fires a trigger that scrubs the profile in the same transaction, so a delete from the Supabase dashboard behaves the same way.

| Deleted | Kept (invoice record) |
|---|---|
| Name, phone, email, photo and notification settings on the profile | The profile row as an anonymised tombstone (`deleted_at` set) |
| Addresses, wishlist, cart | Orders and order items, including the address snapshot on each order |
| Support / RFQ / delivery chats and their messages | Payments, refunds, quotes, RFQs, returns |
| Notifications, device tokens | Business profile company name, VAT TIN and address (printed on B2B invoices) |
| Business contact name and phone, licence file | Reviews, without the author's name |
| Chat attachments and business documents in Storage | Bank slips (payment evidence) |
| The auth user: identities and sessions. The same phone or email can sign up again as a new person. | An `audit_logs` row: role and reason code, no personal data |

## Testing it

```
flutter analyze && flutter test --exclude-tags golden   # 181 tests
supabase test db                                         # 209 pgTAP tests incl. 09_account_deletion
cd supabase/functions && deno test _shared/              # 18 tests incl. account_flows_test
```

- `test/core/router/app_router_test.dart` covers the `launchRedirect` matrix (splash, language, intro, link kept, only in-app links, riders and staff skip the intro, sign-in never held). It also checks that every role is forbidden from every other role's home and account paths.
- `test/features/onboarding/launch_test.dart` covers:
  - first launch through all three slides, picking Khmer, Skip, and a second launch;
  - **each test user (customer, business, rider, staff) landing on their home and getting No access elsewhere**;
  - S-01 holding a deep link while the profile loads.
- `test/features/account/account_test.dart` covers:
  - S-08a and S-08 for customer and business;
  - edit profile validation and saving;
  - the language sheet;
  - sign-out cancel and confirm;
  - delete: tick, Keep account, then Delete → **signed out at guest Customer Home**;
  - an order in progress refusing deletion.

Run against the local stack (`supabase start`, `supabase functions serve`) with the seed users (password `password123`):
- No session → 401.
- `vuthy@kstore.example` (rider) → `not_allowed`.
- `dara@kstore.example` → `has_active_orders` (an order out for delivery and an open return).
- After those were finished, deleting Dara with a chat file in Storage returned `deleted`. Her profile was scrubbed, the auth user and the file were gone, both orders and payments remained, the audit row read `{"role":"customer","reason":"not_using"}`, and her password no longer signed in.
- Run `supabase db reset` afterwards to get the seed back.

## Decisions and assumptions

- **Deletion is refused while an order or return is open** (agreed). This keeps COD deliveries and refunds from being stranded on a deleted account.
- **Edit profile covers name and email only** (agreed). The photo and changing the phone by SMS code are follow-ups, so the S-08b "Change photo" and "Change" controls are not shown.
- Customers and business buyers can delete themselves; riders and staff cannot.
- The profile stays as a tombstone because orders, RFQs and returns reference it `on delete restrict`. The FK from `profiles.id` to `auth.users` was dropped for this; the delete trigger guarantees no orphan keeps personal data.
- Users can no longer edit `profiles.phone` directly (it now follows sign-in). This closes a gap left in F04.
- The onboarding progress is its own device flag, separate from the saved locale. Otherwise tapping a language card on S-02 would skip ahead before Continue.
- **Design deviations:**
  - The bottom bar has two tabs until the other tabs exist.
  - The wishlist, address and cart counts are left out until those features exist.
  - The bell on S-08 waits for S-07.
  - The guest footer "version 1.0.0" is left out; showing it needs `package_info_plus`.
- Golden tests are Windows-generated and differ on macOS. They were already failing locally before F06 and CI excludes them.

## Follow-ups

- S-08b photo upload (needs an `avatars` bucket and `image_picker`) and phone change by OTP (Auth `phone_change`, then sync to `profiles.phone`).
- An access token issued before deletion stays valid until it expires (Auth JWT expiry, 1 h by default). It can read only the scrubbed tombstone and kept order records, and could still insert rows (an address, say) against the tombstone. Hardening options: shorten JWT expiry, or add a `deleted_at is null` check to the own-row write policies.
- S-08d notification settings, S-07 inbox, the Orders/Wishlist/Returns/Addresses screens, Help, Terms, and the B-01 business upgrade replace the "coming soon" toasts.
- Native Khmer review of the new strings (`intro*`, `account*`, `editProfile*`, `delete*`, `signOut*`).
- Rider and admin account areas (their own nav "Account" / "More") come with the rider app and back-office tasks.

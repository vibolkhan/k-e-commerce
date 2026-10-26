# F04 — Supabase schema, RLS & seed data

The whole database in one go: tables, statuses, Row-Level Security, seed data and tests. Requirements: PRD §9 data model, App Flow §5 (statuses) and §7 (business rules).

## Running it

The Supabase CLI is pinned to **2.120.0** (CI uses the same version). You need Docker running.

```
npx supabase@2.120.0 db start     # first start applies migrations + seed
npx supabase@2.120.0 db reset     # rebuild from scratch after changing migrations or seed
npx supabase@2.120.0 test db      # pgTAP schema + RLS tests
npx supabase@2.120.0 start        # full stack (API, Auth, Studio) to use from the app
```

To point the app at it, take the API URL and anon key from `npx supabase@2.120.0 status` and put them in `config/env.json`. The KHR line then reads the seeded rate (4,100).

CI (`.github/workflows/ci.yml`, job `database`) runs `supabase db start` and then `supabase test db` on every PR to `main`.

## Layout

```
supabase/
  config.toml
  migrations/
    …000100_extensions_enums.sql    pgcrypto, pg_trgm, postgis; every status enum
    …000200_helpers.sql             set_updated_at, audit_logs + audit_row, guard_columns
    …000300_accounts.sql            profiles, staff_members, business_profiles, delivery_zones,
                                    addresses, device_tokens; role helpers; sign-up trigger
    …000400_catalog.sql             categories, products, product_variants, prices, warehouses,
                                    stock, stock_movements, variant_availability (view),
                                    collections, collection_items, banners, content_pages
    …000500_commerce.sql            carts, cart_items, wishlists, orders, order_items, payments, refunds
    …000600_delivery.sql            riders, rider_zones, deliveries, rider_locations
    …000700_b2b.sql                 rfqs, rfq_items, quotes, quote_items
    …000800_after_sales.sql         returns, return_items, reviews
    …000900_engagement_admin.sql    conversations, messages, notifications, app_settings
    …001000_rls.sql                 RLS on every table, all policies, grants, column guards, audit triggers
    …001100_realtime_storage.sql    realtime publication, storage buckets + policies
  seed.sql                          design catalogue, zones, settings, demo users and orders
  tests/database/*.test.sql         pgTAP
```

Delivery zones sit in the accounts migration because an address looks up its zone when it is saved.

**Adding to the schema later:** write a new migration. A new table needs `alter table … enable row level security` and its own policies. The schema test fails if any public table has RLS off or has no policy. To keep `updated_at` current, add a `set_updated_at` trigger. Supabase grants `anon` and `authenticated` full table privileges on new tables by default, so revoke the writes you don't want.

## Conventions

- **Money:**
  - Stored as integer US cents (`*_cents`), the same unit as F03's `formatUsd`.
  - Retail prices include 10% VAT; `orders.tax_cents` is the VAT share already inside the total.
  - Quotes add VAT on top, as the design shows (RFQ-0312: $2,055.00 + $205.50 VAT = $2,260.50). `prices_include_tax` records which kind a row is, and a check enforces `total = subtotal + delivery (+ tax when it is added on top)`.
- **Cambodia only:** there is no countries table; currency is USD everywhere. Adding countries later is an additive migration.
- **Translations:** translatable text is `jsonb` such as `{"en": "...", "km": "..."}`, with `en` required. Product Khmer names are empty in the seed, matching A-05a "Translation missing".
- **Common columns:** every table has `id`, `created_at` and `updated_at`. The exceptions are `profiles.id`, which is the auth user id, `app_settings`, which is keyed by `key`, and `rider_locations.id`, which is a bigint because the table is high volume.
- **Numbers:** orders are `K-10265…`, RFQs `RFQ-0316…`, returns `RET-0088…`. The sequences start past the seeded numbers.

## Statuses (enums)

| Enum | Values |
|---|---|
| `order_status` | pending_payment, awaiting_bank_transfer, confirmed, packing, ready, out_for_delivery, delivered, failed_delivery, cancelled, returned |
| `payment_status` | pending, unpaid_cod, awaiting_confirmation, rejected, paid, expired, refunded, partially_refunded |
| `rfq_status` | submitted, in_review, quoted, revision_requested, accepted, rejected, expired, cancelled |
| `quote_status` | draft, sent, accepted, rejected, expired, superseded |
| `delivery_status` | unassigned, assigned, picked_up, delivered, failed |
| `return_status` | requested, approved, picked_up, inspected, refunded, rejected |
| `verification_status` | pending, approved, rejected |
| `review_status` | pending, published, hidden |

There are also enums for `user_role`, `staff_role`, `payment_method`, `refund_status`, `product_status`, `conversation_status`, `banner_audience`, `return_fee_method` and `stock_reason`. Design labels such as "Quote ready" or "Closed" are UI wording over these values, not separate states.

`payments.provider` is text, not an enum, so ABA PayWay can be added without a migration.

## Roles

`profiles.role` is one of `customer`, `business`, `rider` or `staff`; staff also get one row in `staff_members`.

| DB | App (`AppRole`) |
|---|---|
| `customer` | customer |
| `business` | business |
| `rider` | rider |
| `staff` + `staff_role` | admin (menu by staff role) |

- **Sign-up:** a trigger on `auth.users` creates a `customer` profile and copies the `locale` (en or km) from the user metadata.
- **Business verification:** when sales approve a `business_profiles` row, the user becomes `business`; rejecting the row turns them back into a customer. A rejected applicant who edits their details goes back to `pending`.
- **Blocked users:** `profiles.is_blocked` takes away every role-based right.
- **Invited staff:** staff whose status is `invited` have no rights until they are made `active`.

## Security model

All policies are in `…001000_rls.sql`.

1. **RLS decides the rows.** Policies call the helpers `auth_role()`, `is_staff(variadic staff_role[])`, `is_business()`, `is_verified_business()`, `is_rider()`, `owns_order()`, `rider_has_order()`, `is_related_profile()`, `can_track_delivery()` and `has_received_product()`. All are `security definer` with an empty `search_path`.
2. **Grants decide what can be written at all.** `anon` and `authenticated` have no insert, update or delete on orders, order_items, payments, refunds, stock, stock_movements, deliveries, returns, return_items or audit_logs. Edge Functions write those with the service role (later tasks).
3. **`guard_columns()` triggers decide which columns can change.** Examples:
   - Nobody but the service role can change `profiles.role`.
   - Only sales can change `profiles.is_blocked` and `business_profiles.verification_status`.
   - Only support can change `reviews.status` and `admin_reply`.
   - Quote `status` changes only through Edge Functions.

| Who | Can read | Can write |
|---|---|---|
| Guest | active catalog, prices, stock, live banners and collections, published reviews, active zones, `app_settings`, pages | — |
| Customer | the above + own profile, addresses, cart, wishlist, orders (+ items, payments, refunds, deliveries), returns, reviews, notifications, chats; the rider's contact and location while the order is out for delivery | own profile (safe columns), addresses, cart, wishlist, device tokens, notification read flags; reviews after a delivered order; support chats and messages; a business application |
| Business buyer | as customer, but **no `prices` rows**; own RFQs, quotes once sent, RFQ threads | RFQs (only when verified, status `submitted`, minimum quantity enforced), cancel while submitted; no cart |
| Rider | assigned deliveries and their orders, items and customer contact | own location on a `picked_up` delivery; own on/off duty |
| Staff: catalog | catalog, stock, content, all profiles | catalog, prices, banners, collections, pages, product images |
| Staff: sales | + orders, payments, RFQs, quotes, business profiles, RFQ threads | quotes and quote lines while draft, RFQ assignment, business verification, blocking customers |
| Staff: support | + orders, payments, returns, reviews, support chats | review moderation, chat assignment and replies |
| Staff: super_admin | everything, including `audit_logs` and `staff_members` | settings, zones, staff, riders, warehouses, plus every other staff right |

Status, money and stock changes go through Edge Functions even for super admins.

The **audit log** (ADM-10) records each insert, update and delete on orders, payments, refunds, products, prices, stock, deliveries, business_profiles, staff_members, delivery_zones and app_settings. Each row has the actor (`auth.uid()`) and, for updates, only the changed columns.

**F03 contract:** `app_settings(key text pk, value jsonb)` is readable by everyone; only a super admin can change it, and every change is audited.

### Storage buckets

| Bucket | Public | Write | Read (private) |
|---|---|---|---|
| `product-images`, `banners` | yes | catalog staff | — |
| `review-photos` | yes | own folder `<uid>/…` | — |
| `pod-photos` | no | rider's own folder | owner, sales, support |
| `bank-slips` | no | own folder | owner, sales |
| `business-docs` | no | own folder | owner, sales, support |
| `chat-attachments` | no | own folder | owner, support, sales |

**Realtime:** orders, deliveries, rider_locations, conversations, messages and notifications are published, and RLS applies to subscribers.

## Seed (local only)

All demo accounts use the password `password123`.

| Email | Who |
|---|---|
| chenda@kstore.example | super_admin |
| dalin@kstore.example | sales |
| sophea@kstore.example | support |
| visal@kstore.example | catalog |
| rachana@kstore.example | support, invited (inactive) |
| vuthy@kstore.example, sokun@kstore.example | riders |
| dara@kstore.example | customer with orders, review, return, chat |
| bopha@kstore.example | customer |
| vannak@kstore.example | blocked customer |
| sokha@kstore.example | business buyer, Mekong Desk Co. (approved) |
| lina@kstore.example | applicant, Sovann Trading Co. (pending) |

The rest of the seed comes from the design screens:

- **Catalog:** 15 categories (Electronics has 6 children), 24 products and 40 variants with prices and stock, from A-05, A-05b, A-06 and W-02. This includes the low-stock, out-of-stock and draft cases.
- **Warehouse:** one, "Phnom Penh store".
- **Zones:** Toul Kork, Boeung Kak, Daun Penh, BKK1 (COD limit $300), Sen Sok, and Chbar Ampov (paused). The polygons are rough boxes around each area, not surveyed boundaries.
- **Settings:** every App Flow §7 rule — cut-off, delivery hours and slots, KHR rate, COD limit, stock hold, KHQR expiry, return window and fee, chat reopen window, OTP.
- **Home content:** 4 banners (live, business-only, scheduled, ended), 5 collections and 5 pages.
- **Orders:** K-10248 (delivered), K-10250 (out for delivery, COD) and K-10251 (ready). Also RFQ-0312 (quoted), RFQ-0298 (expired), RET-0087, a support chat and an RFQ thread.
- **Ratings:** product ratings and sales counts are the design's display values. The reviews trigger recalculates a product's rating from its published reviews the first time one changes.
- **Bank details:** the bank account and KHQR merchant id are empty placeholders, as in the design. Set them per environment.

## Tests

`supabase/tests/database/` holds 171 pgTAP assertions, which run as real users through the `tests.login_as(email)` helper.

| File | Covers |
|---|---|
| `00_helpers` | installs pgTAP and the `tests` helpers |
| `01_schema` | RLS and a policy on every table, PRD tables, status enums, the `app_settings` contract, the sign-up trigger |
| `02_anon` | guests: live catalog and rate only; nothing personal; no writes |
| `03_customer` | own rows only; no money, stock or status writes; no self-promotion; zone from pin; review rules; live tracking; blocked users |
| `04_business` | no retail prices or cart; RFQ only when verified and at the minimum quantity; approval flips the role |
| `05_rider` | assigned deliveries only; location only on own picked-up delivery |
| `06_staff` | catalog, sales, support and super_admin per the A-14d matrix; invited staff; audit log contents |
| `07_rules` | reserved ≤ qty, zones, number formats, total checks, POD photo, rating trigger, audit diffs |

## Left for later tasks

- **Edge Functions** for every server-side write: checkout and stock reservation (F10, F15+), KHQR, COD, bank slip, order and delivery status, quote send and accept, returns and refunds, staff invites.
- **Scheduled jobs:** expire unpaid KHQR orders and release their stock, expire quotes, and run `prune_rider_locations()`.
- **Rider ↔ customer chat threads** (`kind = 'delivery'`) are created by the delivery Edge Function.

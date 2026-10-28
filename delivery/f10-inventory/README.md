# F10 — Inventory & stock reservation

Stock is right even when many people check out at once. Every order reserves its units under a row lock, unpaid KHQR holds are released after 15 minutes, and staff adjust stock with a reason that goes in the audit log.
- Requirements:
  - ADM-03: stock per warehouse, adjustments with a reason, low-stock alerts.
  - CAT-05: stock per variant; out-of-stock items cannot be ordered.
  - CHK-04: stock is reserved at order placement and released if payment is not completed within 15 minutes.
- Screens: A-06, A-06a.

## Who can do what

| | Super admin | Catalog | Sales | Support |
|---|---|---|---|---|
| Open A-06 and the history | ✓ | ✓ | View | View |
| Adjust stock (A-06a) | ✓ | ✓ | — | — |
| Low-stock alert in the inbox | ✓ | ✓ | — | — |

- **Client side:** `canEdit(role, PermissionArea.products)` decides whether the Adjust buttons show. View roles see a read-only banner.
- **Server side:**
  - `inventory-manage` answers `forbidden` to anyone but active catalog staff and super admins.
  - `adjust_stock`, `reserve_stock`, `release_stock`, `commit_stock` and the expiry job run only with the service role.
  - Nobody can write `stock`, `stock_movements` or `stock_reservations` through the API.

## Routes

| Path | Screen |
|---|---|
| `/admin/inventory` | A-06. Adjust opens A-06a as a 560 px modal on desktop and a sheet on phones. |

A-05b's "Stock overview" panel links here. The low-stock notification opens it too.

## How stock moves

**Available = on hand (`stock.qty`) − reserved.** Every reserved unit belongs to a `held` row in `stock_reservations`, one per order and variant.

| When | Call | Effect | Ledger row (`stock_movements`) |
|---|---|---|---|
| Order placed, KHQR or COD (F17) | `reserve_stock(order)` | reserved += n; KHQR orders get `reserved_until = now + stock_hold_minutes` | `reserved`, −n available |
| KHQR not paid within 15 min | pg_cron, every minute | `release_expired_reservations()` → `release_stock` | `released`, +n available |
| Cancelled before packing (F19) | `release_stock(order)` | reserved −= n | `released`, +n available |
| Goods leave the store (F20, out for delivery) | `commit_stock(order)` | qty −= n, reserved −= n, `products.sold_count` += n | `sold`, −n on hand |
| A-06a adjustment | `adjust_stock(actor, …)` via `inventory-manage` | qty set, added or removed | `received` / `returned` / `damaged` / `adjustment`, ± on hand |

- **Row locks:**
  - Each function locks the order row first.
  - It then takes the stock rows it touches with `SELECT … FOR UPDATE`, ordered by `variant_id`.
  - Two checkouts for the last unit queue up on the same row, and the second one sees what the first one took.
  - Locking in one order means multi-item orders never deadlock.
- **All or nothing:** if any line is short, `reserve_stock` changes nothing and returns `{status: "insufficient", items: [{variant_id, requested, available}]}`. Cart and checkout (F16/F17) use that for C-06c.
- **Idempotent:**
  - Reserving an order that already holds stock does nothing.
  - Releasing or committing twice moves nothing twice.
  - A released KHQR order can be reserved again when the customer retries (F18).
- **Backstop:** the existing check `reserved <= qty` would reject an oversell even if a caller skipped the lock.
- **The expiry job releases stock only.** It does not change the order or payment status. F18 owns "Payment time expired", retry and cancel.
- **Low-stock alerts:**
  - When an adjustment or reservation brings available to the alert level or below, the function returns the crossing.
  - The Edge Function layer then notifies active catalog staff and super admins (`admin_low_stock`, which opens `/admin/inventory`).
  - `stock.low_alerted_at` makes it once per crossing; it re-arms when available goes back above the level.
  - A failed alert never fails the stock change.

### For later tasks (F17 – F20, F31)

Import from `supabase/functions/_shared/stock_flows.ts` with `orderStockDeps()` from `stock_deps.ts`:

```ts
const stock = orderStockDeps(service);
await reserveForOrder(stock, orderId);  // reserved | insufficient{items} | not_found | invalid_status
await releaseForOrder(stock, orderId);  // released{units} | not_found
await commitForOrder(stock, orderId);   // committed{units} | not_held | not_found
```

- `reserve_stock` accepts orders in `pending_payment`, `awaiting_bank_transfer` or `confirmed`.
- Putting stock back after it was committed (cancel after dispatch, return refunds) is F20/F31. Until then staff use A-06a with "Returned to stock".

## Database

```
supabase/
  migrations/20261102000100_inventory.sql
    pg_cron                       release-expired-stock, every minute
    stock_reservations            order × variant × warehouse, qty, held | committed | released;
                                  staff read, no client writes
    stock.low_alerted_at          once-per-crossing low-stock flag
    orders_reserved_until_idx     partial index for the expiry scan
    reserve_stock(order)          ┐
    release_stock(order)          │ service role only, row locks in variant order
    commit_stock(order)           │
    release_expired_reservations()┘ FOR UPDATE SKIP LOCKED, 500 orders per run
    adjust_stock(actor, variant, mode, qty, reason, note, low_stock_at)
                                  acts as the staff member (audit_logs actor); never below reserved
    low_stock_recipients()        active catalog staff + super admins
    inventory_admin_list(search, filter, limit, offset)
                                  A-06 rows, summary tiles and filter counts; any staff
    stock_history(variant?, limit)
                                  ledger with staff names and order numbers; any staff
  functions/
    inventory-manage/             staff adjust (A-06a)
    _shared/stock_flows.ts        manageInventory, reserveForOrder/releaseForOrder/commitForOrder,
                                  alertLowStock
    _shared/stock_deps.ts         stockDeps(), orderStockDeps()
    _integration/stock_race_test.ts
  tests/database/14_inventory.test.sql
  seed.sql                        K-10252 (confirmed COD) and K-10253 (packing) hold the
                                  seeded reserved units, so the invariant holds on a fresh seed
```

- **Delta meaning:** in `stock_movements`, `delta` is the change in *available* for `reserved` / `released` rows, and the change in *on hand* for every other reason.
- **States:**
  - Out: available ≤ 0.
  - Low: available ≤ alert level.
  - OK: anything above that.
  - Not stocked: no stock row yet. Adding stock creates the row.

### `inventory-manage`

Body: `{ action: "adjust", variant_id, mode, qty, reason, note?, low_stock_at? }`. HTTP 200 with a `status` for every outcome; a malformed body is 400, and no session is 401.

| `mode` | `qty` | Allowed `reason` |
|---|---|---|
| `add` | 1 – 100,000 to add | `received`, `returned`, `adjustment` |
| `remove` | 1 – 100,000 to remove | `damaged`, `adjustment` |
| `set` | 0 – 100,000, the counted number | `adjustment` |

| `status` | Meaning |
|---|---|
| `adjusted` | `{on_hand, reserved, available, low_stock_at, delta}` |
| `below_reserved` | `{reserved}`: open orders hold more than the result would leave |
| `invalid` | `{errors: [{field, code}]}`: `required`, `invalid` or `too_long` (note over 500) |
| `not_found` | Unknown variant |
| `forbidden` | Not active catalog staff or a super admin |

## App

`lib/features/inventory/{data,domain,presentation}`

- **A-06 (`inventory_list_page.dart`):**
  - Breadcrumb, then four tiles: Low stock, Out of stock, Reserved units, Stock value at retail price. `AdminStatTile` is new in `admin/presentation`.
  - Search, plus Needs restock / Out of stock / All SKUs chips with counts. The default is Needs restock (low + out).
  - The 15-minute note.
  - A table on desktop: SKU, product · variant, on hand, reserved, available, alert at, status, last change, Adjust.
  - Cards on phones.
  - Paging, the restock count, and "View adjustment history".
- **A-06a (`adjust_stock_dialog.dart`):**
  - Item header with its pill.
  - Add / Remove / Set exact count option tiles.
  - Quantity with "units", and the reasons for the chosen mode.
  - Optional note.
  - A live "On hand after saving 4 → 54 OK" strip.
  - The quantity is checked as you type: whole number, at most 100,000, not below what orders hold, and not unchanged.
  - Save asks for confirmation (a stock change), then refreshes the list, the history, A-05 and the sidebar badge.
  - The last five changes of the SKU are listed in the dialog.
  - The page-head "Adjust stock" first opens a SKU search sheet.
- **History sheet (`stock_history_sheet.dart`):** the latest 50 movements with who made them or which order.
- **Strings:** `inventory*` keys in `app_en.arb` and `app_km.arb`. The pills reuse `catalogStock*`.

## Testing it

```
flutter analyze && flutter test                          # 349 tests (22 new)
supabase db reset && supabase test db                     # 356 pgTAP tests incl. 14_inventory (60)
cd supabase/functions && deno test _shared/               # 82 tests incl. stock_flows_test (10)
STOCK_IT=1 deno test --allow-net --allow-env _integration/  # 3 concurrency/load tests, needs the local stack
```

- **`_integration/stock_race_test.ts`** runs against the local API, where each request is its own transaction:
  - **Last unit:** two orders for the last unit fire at the same moment, 10 rounds. Exactly one is `reserved` and one `insufficient` each time, ending at on hand 1 / reserved 1.
  - **Load:**
    - 150 orders reserve at once over two variants, half of them multi-line in either order.
    - Then commits, releases and retries all run at the same time.
    - Afterwards `reserved = Σ held`, `on hand = start − Σ shipped`, available ≥ 0, and nothing is sold beyond the starting stock, with no deadlocks or errors.
  - **Expiry:** a back-dated KHQR hold comes back after `release_expired_reservations()`.
  - It deletes everything it creates. It still leaves audit rows behind, so run `supabase db reset` before `supabase test db`. CI runs pgTAP first, then this.
- **`14_inventory.test.sql`** covers:
  - the seed invariant and the cron job;
  - the service functions refused to staff, and no direct stock writes;
  - A-06 summary, counts, ordering, available, last change and not stocked;
  - support reading the history; customers kept out;
  - reserve, idempotency, shortfall, release, commit;
  - adjust: note, actor, audit log, below reserved, reason/mode rules, never-stocked variants;
  - low-stock crossing and re-arm;
  - the expiry job and the alert recipients.
- **`stock_flows_test.ts`** covers:
  - who may adjust; 401/400;
  - field validation and reasons by mode;
  - database outcomes;
  - the alert fan-out to staff with the inventory route;
  - a failed alert not failing the change;
  - `reserveForOrder` passing shortfalls back.
- **Flutter:**
  - `inventory_domain_test.dart`: states, row mapping, preview maths, form problems, reasons by mode, payload, outcomes, `formatUsdWhole`.
  - `inventory_page_test.dart`: tiles, default filter, pills, last change, filters and search, read-only support, retry, phone cards, history sheet.
  - `adjust_dialog_test.dart`: add with preview, confirm, payload and refresh; cancelling the confirmation; remove below reserved; set count with no change; a server refusal kept in the dialog; picking a SKU from the page head; the phone sheet.

**Local-stack check** (seed users, password `password123`):

| Step | Result |
|---|---|
| visal opens `/admin/inventory` | Low 5, Out 3, Reserved 6. Needs restock lists 8 SKUs, out of stock first. |
| Adjust LMP-LED-WHT → Add 50, Received from supplier | Confirm, then "Stock updated. LMP-LED-WHT now has 54 on hand."; the row turns OK |
| Adjust MUG-4-WHT → Set exact count 15 | chenda and visal get "Ceramic Coffee Mug Set (4 pcs) · White has 15 left. Low-stock level is 20." in the inbox (checked through the Edge Function) |
| Remove 4 from LMP-LED-WHT before adding | Blocked: "1 unit is held for an open order…" |
| sophea (support) opens `/admin/inventory` | Read-only banner, no Adjust |

## Owner setup (hosted)

1. Turn on **pg_cron**: Database › Extensions (the migration runs `create extension if not exists pg_cron`). Then `supabase db push`. The job `release-expired-stock` appears under Integrations › Cron.
2. Deploy the function: `supabase functions deploy inventory-manage`. It uses `verify_jwt = true` and the default `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`.
3. The hold time is `app_settings.stock_hold_minutes` (15). The Store & rules screen (F39) will edit it.

## Decisions and assumptions

- **Reserve at placement for KHQR and COD; commit when goods leave.** A-06 counts "units in unpaid or packing orders" as reserved, so a paid order keeps its hold until fulfilment (F20) commits it.
- **The expiry job only releases stock.** Marking the payment expired, the C-09b screen, retry and the push are F18.
- **One warehouse** ("Phnom Penh store", Cambodia only). The functions pick the first active warehouse, as F09 does. `stock_reservations` records the warehouse, so more can come later.
- **Low stock is measured on available**, so reserved units count. HP-PRO-BLK with 12 on hand, 1 reserved and an alert level of 15 is Low, as in the design.
- **Reasons:**
  - The ledger keeps `stock_reason`.
  - A-06a shows friendlier labels. "Lost", "Used in store" and "Count correction" all record `adjustment`, so their label goes in front of the note.
- **Low-stock alerts go from the Edge Function layer**, not SQL. There is no pg_net / vault set-up, and push needs the notify pipeline. Alerts go to catalog staff and super admins.
- **Alert levels** are set per variant (`stock.low_stock_at`). The server accepts a new level with an adjustment, but A-06a doesn't show the field because the design has none. Editing levels in the UI is left for later.
- **Seed:** two Bopha orders (K-10252, K-10253) were added to back the seeded reserved units. `06_staff` now expects sales to see 5 orders.
- **Design deviations:**
  - **Reason:** chips filtered by mode instead of a select, so every option is one tap and readable by a screen reader.
  - **Export:** shown but disabled with "CSV export arrives with Reports." (F38).
  - **History:** "View adjustment history" opens a sheet; the design has no screen for it.
  - **Confirmation:** saving asks for it first (CLAUDE.md: confirm money and stock actions).
- **Not done here:**
  - Wiring reserve/release/commit into checkout, payment, cancel and fulfilment (F17 – F20).
  - Restocking on returns (F31).
  - The dashboard low-stock tile (F37).
  - Stock reports (F38).
- **Pre-existing, untouched:**
  - `dart format` reports `test/features/catalog/product_editor_test.dart` as unformatted on `dev`.
  - `deno fmt --check` reports some older Edge Function files on this Windows checkout. They were already failing before F10.

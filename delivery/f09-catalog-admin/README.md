# F09 — Catalog management (admin)

Staff can create and maintain the whole product catalogue: list, edit, import and archive products, with every price change in the audit log.
- Requirements: ADM-02 (product management, CSV import), CAT-01 (names and descriptions in Khmer and English, images, category, brand, variants, SKU, barcode scan), CAT-07 (B2B quote flag with a minimum quantity).
- Screens: A-05, A-05a, A-05b, A-05c, A-05d, A-05e.

## Who can do what

| | Super admin | Catalog | Sales | Support |
|---|---|---|---|---|
| Open A-05 and products | ✓ | ✓ | View | View |
| Create, edit, import, archive, restore | ✓ | ✓ | — | — |

- **Client side:**
  - `canEdit(role, PermissionArea.products)` (`staff_permissions.dart`) decides which buttons show and whether fields are read-only.
  - `adminRedirect` sends read-only roles away from `/admin/catalog/new` and `/admin/catalog/import`, back to the list.
- **Server side:**
  - catalog-manage and catalog-import answer `forbidden` to anyone but active catalog staff and super admins.
  - The SQL write functions can only be called with the service role.

## Routes

| Path | Screen |
|---|---|
| `/admin/catalog` | A-05 product list |
| `/admin/catalog/new` | A-05a – A-05c for a new product |
| `/admin/catalog/:id` | A-05a – A-05c (read-only for view roles) |
| `/admin/catalog/import` | A-05d on phones. On desktop it opens as a modal over A-05. |

## Database

```
supabase/
  migrations/20261101000100_catalog_admin.sql
    products + highlights jsonb [{en,km}], options jsonb [{name{en,km}, values[]}],
               same_day, rfq_multiple, updated_by
    product_images         ordered gallery (sort 0 = main image), alt {en required, km},
                           optional variant; public read of visible products,
                           catalog writes; audited
    private.act_as(actor)  sets request.jwt.claims so audit_row() records the staff member
    catalog_save_product(actor, product)        one transaction: product, variants,
                                                prices, images, opening stock
    catalog_set_status(actor, ids, status)      archive / restore
    catalog_set_category(actor, ids, category)  bulk move
    catalog_import(actor, products)             all-or-nothing, as drafts
    catalog_existing_skus(skus)                 import preview
      ↑ service role only
    catalog_admin_list(tab, search, category, stock, quote_only, limit, offset)
                           A-05 rows + tab counts, staff only (runs as the caller)
    product_price_history(product)   A-05b, catalog staff + super admin
    catalog_archive_impact(product)  A-05e: variants, in stock, open orders, open RFQs
  functions/catalog-manage, functions/catalog-import
  functions/_shared/catalog_flows.ts, import_flows.ts, catalog_deps.ts (+ *_test.ts)
  tests/database/13_catalog_admin.test.sql
```

- **Specs** are saved as an ordered `[{"name","value"}]`. Rows written before F09 may still be an object; the app reads both.
- **Price changes are audited.** The F04 `audit` trigger on `prices` logs every insert and change. F09 makes the actor the staff member rather than null (service role) and skips no-op price updates, so the log only has real changes. `product_price_history` reads that log for the product's variants.
- **Opening stock:** a new variant can get its first on-hand quantity in the editor or from a CSV `qty` column. It is written as a `stock` row plus a `received` movement ("Opening stock") with the actor. All later changes are A-06 (F10).
- **Variants:** a saved variant is never deleted, because it may be in orders. Dropping it from the editor or the options turns its Sell switch off.
- **Images:** an image left out of a save is removed from `product_images`. The file stays in Storage.

### `catalog-manage`

The caller must be active catalog staff or a super admin; anyone else gets `forbidden`. With no session the answer is 401, and a malformed body (unknown action, bad id) is 400.

| Action | Body | Results |
|---|---|---|
| `save` | `product` (below) | `saved` (+ `id`), `invalid` (+ `errors: [{field, code}]`), `sku_taken` (+ `sku`), `not_found` |
| `archive` | `id` | `updated` (+ `count`) |
| `restore` | `id` | `updated`; the product comes back as a draft |
| `bulk_archive` | `ids` (1–200) | `updated` |
| `bulk_category` | `ids`, `category_id` | `updated` |

- **`product` fields:**
  - `id?`, `category_id`, `slug?`, `brand?`
  - `name{en,km}`, `description{en,km}`, `highlights[{en,km}]`, `specs[{name,value}]`, `tags[]`, `options[{name{en,km},values[]}]`
  - `status` (`draft` | `active`), `is_best_seller`, `same_day`
  - `rfq_enabled`, `rfq_min_qty`, `rfq_multiple`
  - `variants[{id?, sku, barcode?, attributes{}, active, price_cents, compare_at_cents?, initial_qty?}]`
  - `images[{id?, path, alt{en,km}, variant_sku?}]`, in display order
- **Validation** (codes `required`, `too_long`, `too_many`, `invalid`, `duplicate`):
  - **Name and category:** an English name is required (up to 120 characters), and so is a category.
  - **Variants:** from 1 to 100. The SKU uses letters, numbers, `.`, `_` or `-` and is unique across the catalogue. The price is from $0.01 to $100,000. The compare-at price must be above the price.
  - **Quote:** `rfq_min_qty` is required when quotes are on.
  - **Images:** up to 10. Each path must be under `products/` and each needs English alt text.
  - **Text limits:** 1,000 characters per description, 10 highlights, 30 spec rows, 20 tags, and 3 options.
- The editor runs the same checks first (`ProductDraft.validate()`), using the same field paths.

### `catalog-import` (A-05d)

Body: `{ action: "preview" | "commit", csv, mapping: { "<column>": "<field>" } }`.
- **Fields:** `name_en`, `name_km`, `description_en`, `description_km`, `brand`, `category`, `sku`, `barcode`, `price_usd`, `qty`, `tags`, `handle`, `variant`, `ignore`.
- **Required:** `name_en`, `sku`, `price_usd` and `category`.

| Result | When |
|---|---|
| `preview` (+ `rows`, `valid`, `products`, `errors[{row, code, value?}]`) | checked, nothing written |
| `imported` (+ `products`, `variants`, `skipped`, `errors`) | the valid rows were imported in one transaction |
| `no_mapping` (+ `missing`) | a required field has no column |
| `empty`, `too_large`, `unreadable`, `forbidden` | |

- **Rows:**
  - One row is one variant. Rows that share a `handle` become variants of one product, and the first named row gives the product's name, category and brand.
  - `variant` reads "Colour: Black; Size: M". The product's options are built from it.
  - Row numbers are spreadsheet rows, so the header is row 1.
- **Values:**
  - Prices can be `49`, `$49.50` or `1,250.00` (USD, VAT included).
  - A category matches its slug, its English name or "Electronics › Audio".
- **Row errors:** `name_missing`, `sku_missing`, `sku_invalid`, `sku_duplicate` (twice in the file), `sku_exists` (already in the catalogue), `price_missing`, `price_invalid`, `qty_invalid`, `category_missing`, `category_unknown`, `too_long`. Rows with errors are skipped and the rest are imported.
- **Imported products start as drafts,** since they have no images yet.
- **Limits:** 5,000 rows and 2 MB per file.
- **Template:** `delivery/f09-catalog-admin/products_template.csv`. Its preview on the local stack returns 3 rows, 3 valid, 2 products.

## App

Feature folder: `lib/features/catalog/{data,domain,presentation}`.

- **A-05 list:**
  - **Tabs:** All / Active / Draft / Archived, with counts. All leaves archived products out.
  - **Search and filters:** search by name or SKU (debounced), a Category picker (a parent includes its children), Stock chips (In stock / Low / Out), and a "Quote enabled" chip.
  - **Rows:** a table on desktop and cards on phones. Each shows the thumbnail, "SKU · Brand", category, variant count, price or price range, the stock pill ("52 · 1 out", "4 · low", Out of stock, Not stocked), the quote pill ("Min 5" or Off), status, and when it was last updated and by whom. Pages hold 25 rows.
  - **Bulk actions:** select rows, then Archive (asks first) or Change category.
- **A-05a General:**
  - **Text:** English and Khmer names and descriptions, with a "Translation missing" pill and a character count.
  - **Lists:** highlights in both languages, and specification rows.
  - **Organisation:** category picker, brand and tags.
  - **Visibility switches:** Active, Show in Best sellers, Same-day delivery.
  - **Summary:** created and last updated (date and who), sold count and rating.
- **A-05b Variants & pricing:**
  - **Options:** name plus value chips. Every combination becomes a variant, with SKUs suggested from the existing prefix (`HP-PRO` + Red → `HP-PRO-RD`) and the current price as the default.
  - **Variant rows:**
    - Editing: SKU, barcode (with camera scan on Android, iOS, web and macOS), USD price, and the Sell switch.
    - Read-only: the KHR preview at the settings rate, and On hand / Reserved with a stock pill.
    - New variants get an Opening stock field instead of the stock figures.
  - **Business quotes:** the switch, the minimum quantity and "order in multiples of", with the "never see the retail price" note.
  - **Side panels:** stock overview, and price history ("HP-PRO-BLK: $52.00 → $49.00 · Today, 9:12 AM · Chenda Lim").
- **A-05c Images:**
  - **Adding:** "Add images" takes JPG, PNG or WebP up to 5 MB, 10 per product, and uploads each to `product-images/products/<product id>/…`. A product not saved yet uses a `new-…` folder.
  - **Ordering:** move earlier or later, and "Set as main". The first image is the main image.
  - **Delete** asks first.
  - **Per image:** an English description (required) and a Khmer one, and which variant it shows.
  - **Missing descriptions:** a warning banner, and save is blocked until each image has one.
  - Photo guidelines from the design are shown beside the images.
- **Saving:**
  - **Before calling the server:** the editor checks first and jumps to the first tab with a problem. If any saved variant's price changed, it asks "Change prices?" first, since that is a money action.
  - **Server problems** (`invalid`, `sku_taken`) land on the same fields.
  - **Leaving with unsaved changes** (back, or Products in the breadcrumb) asks first.
- **A-05e Archive:** shows the variants and units in stock, open orders ("will still ship") and open quote requests, then asks to confirm. Archived products show Restore, which brings them back as a draft.
- **Preview** shows the saved product read through `ProductReadRepository`, the same reads and RLS customers get. It shows the shopper card (USD and KHR, main image) and, when quotes are on, the business buyer card (no price, minimum quantity). It notes when the product isn't active yet or has unsaved changes. F11/F13 can reuse `ProductReadRepository` and `productViewFromRow`.
- Strings are `catalog*` keys in `app_en.arb` and `app_km.arb`.

## Testing it

```
flutter analyze && flutter test                          # 327 tests (55 new)
supabase test db                                          # 296 pgTAP tests incl. 13_catalog_admin (30)
cd supabase/functions && deno test _shared/               # 72 tests incl. catalog_flows_test, import_flows_test (15)
```

- `test/features/catalog/catalog_domain_test.dart` covers:
  - translations and payload shape;
  - validation paths and tabs;
  - unsaved-change detection;
  - option combinations and SKUs;
  - CSV head parsing (quotes, BOM, empty counts) and column auto-matching;
  - Edge Function answers, labels, price input;
  - the matrix's `canEdit`;
  - Supabase row mapping for the editor and for customers, including no price for business buyers.
- `catalog_list_test.dart` covers:
  - tabs, pills, search, category, stock and quote filters, and clearing them;
  - bulk archive with its confirmation, and bulk move;
  - paging, Edit, read-only sales, phone cards, and retrying after a failure.
- `product_editor_test.dart` covers:
  - missing-translation flags; highlights, specs and tags saved;
  - a new product's required fields, KHR preview and opening stock, and landing on its page;
  - the unsaved-changes guard;
  - the price-change confirmation; options building variants; the quote minimum; `sku_taken` on its field;
  - images: upload with type and size checks, required descriptions, set as main, delete;
  - archive with impact, restore;
  - Preview; read-only support; read-only roles kept out of `/new`; phone layout; a missing product.
- `import_wizard_test.dart` covers:
  - upload, match columns, review errors, copying the error report, and import;
  - a missing required column; empty and too-large files;
  - the phone page.
- `admin_domain_test.dart` covers `adminRedirect` for the catalog routes, for every role.
- `13_catalog_admin.test.sql` covers:
  - the write functions are refused to API users;
  - trimming and Khmer dropping, created_by, opening stock and its movement;
  - image order; audited inserts with the actor;
  - `sku_taken`, required name and quote minimum, image alt text;
  - an update logging only the changed price, with old, new and actor;
  - reordering changing the main image;
  - price history for catalog staff, refused to sales;
  - the list RPC by SKU with the main image;
  - visitors seeing prices and images, business buyers seeing none;
  - archive hiding the product and its images;
  - sales unable to add images.

Checked on the local stack (`supabase start`, `supabase functions serve`, seed password `password123`), using the same calls and selects the app makes:

| Step | Result |
|---|---|
| As visal: upload a PNG to `product-images/products/new-e2e/` | stored; public URL returns `200 image/png` |
| As visal: save "E2E Studio Monitor", active, Colour Black/White at $129/$139, 8 opening stock on Black, quote min 4, one image with alt text | `saved` |
| Signed out: read it with the app's customer select | name, both variants with prices, the image and its alt text; availability 8 / 0 |
| As chenda: change Black to $119 | `saved`; `product_price_history` (as visal) shows 12900 → 11900 by Chenda Lim, plus both launch prices by Visal Keo; `audit_logs` has the update with Chenda as actor |
| As sokha (business buyer): read its prices | none |
| As visal: archive | `updated`; signed out, the product is gone |
| As dalin (sales): restore | `forbidden` |
| As visal: save with SKU `HP-PRO-BLK` | `sku_taken` |
| As visal: preview the template CSV | 3 rows, 3 valid, 2 products |

The pgTAP files that count audit rows (`06_staff`, `07_rules`, `13_catalog_admin`) expect a fresh seed. After trying things by hand, run `supabase db reset` before `supabase test db`.

## Owner setup (hosted)

1. Apply the migration: `supabase db push`.
2. Deploy the functions: `supabase functions deploy catalog-manage catalog-import`. Both use `verify_jwt = true` (see `supabase/config.toml`) and only need the default `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
3. **Camera barcode scan:** nothing to configure.
   - iOS and macOS have `NSCameraUsageDescription` ("Scan product barcodes when adding products."). macOS also has the camera entitlement.
   - Android gets the camera permission from `mobile_scanner`.
   - On the web the scan needs HTTPS (or localhost).

## Decisions and assumptions

- **"Appears in the app"** (agreed): the customer app has no product screens yet (F11 home and list, F13 detail). F09 adds the shared customer read (`ProductReadRepository`), and the admin Preview shows the product through it. The database tests and the local-stack check prove a signed-out customer can read the new product with its prices and images.
- **Barcode** (agreed): a typed field per variant, plus a camera scan where a camera is supported (`mobile_scanner`).
- **No CSV export** (agreed): A-05 has no Export button. ADM-02's export can come with reports (F38).
- **One country, one price:** each variant has one USD price including VAT, and KHR is display only. Cambodia only per the app flow, so there is no per-country price (CAT-01, ADM-02).
- **Stock:** F09 only sets opening stock for new variants. On hand and Reserved are read-only here. Adjustments with a reason, alerts and reservation are F10 (A-06).
- **Every write goes through an Edge Function**, as CLAUDE.md requires for money and stock. The F04 policies that let catalog staff write `products` and `prices` directly are left as they are (`06_staff` relies on them). The app never uses them.
- **"Show in Best sellers"** is `is_best_seller`. **"Same-day delivery"** is the new `same_day` flag. Checkout does not use it yet; that is F17/F18.
- **"Order in multiples of"** is stored as `rfq_multiple`; the RFQ screens (F26) enforce it.
- Restore brings a product back as a draft, so it is checked before going live again.
- **Design deviations:**
  - Images are reordered with earlier/later buttons and "Set as main", not drag and drop, so it works with a keyboard and a screen reader.
  - The Stock filter is chips (In stock / Low / Out) rather than a select. The Category filter opens the category tree in a sheet.
  - A-05b's variant table is one card per variant, so it fits a phone and the narrow admin column on desktop.
  - The Price history panel lists price changes only, not "variant added" events. Variant additions show as their launch price.
  - Leaving with unsaved changes is guarded for back and the breadcrumb. Leaving through the sidebar is not guarded.

# F11 — Home, categories & product list

Shoppers can now browse the shop: a real home screen with banners, the same-day countdown, categories and curated rails; a Categories tab with a left rail; and a product list with quick chips, a filter sheet and a sort sheet. It works for guests, customers and business buyers, on phones and the web. Lists load page by page, photos are cached, every section has a skeleton while loading, and empty or failed states say what to do next.

- Requirements: CAT-02 (category tree with icons and banners), CAT-04 (filters and sorting), CAT-06 (home banners and curated collections). Also AUTH-03 (guests browse) and the B2B rule that business buyers never see retail prices.
- Screens: C-01 Home (B-00 for business buyers), C-02 Categories, C-03 Product list, C-03a Filters sheet, C-03b Sort sheet.

## Who sees what

| | Guest | Customer | Business buyer |
|---|---|---|---|
| Browse home, categories, lists | ✓ | ✓ | ✓ |
| Prices (USD + ≈ KHR) | ✓ | ✓ | — "Price on quote" + minimum quantity |
| Price filter, "Under $50" chip, price sorts | ✓ | ✓ | — |
| Same-day countdown on home | ✓ | ✓ | — "You'll see prices after sales sends your quote." |
| Banners and collections | `all` + `retail` | `all` + `retail` | `all` + `business` |
| Home featured rail | Best sellers | Best sellers | Popular for offices |
| "Buying for a business?" tile | ✓ | ✓ | — |
| Location pill | "Phnom Penh"; tap asks to sign in | Default address, switchable for the session | Same as customer |

Enforced on the server, not just hidden in the app:

- `catalog_browse` runs as the caller, so RLS still removes prices for business buyers. It also ignores price filters and price sorts for them, so filtering can't be used to probe prices.
- A collection whose audience doesn't match the caller browses as empty. Banners are filtered by audience in the query (RLS doesn't look at audience).
- Only `active` products and variants are listed, even for staff who can read drafts.

## Routes

| Path (also under `/business`) | Screen |
|---|---|
| `/customer` | C-01 Home (tab 1) |
| `/customer/categories` | C-02 Categories (tab 2) |
| `/customer/categories/:slug` | C-03 for a category and its subcategories |
| `/customer/collections/:slug` | C-03 for a collection (home "See all", banners) |
| `/customer/search` | C-04 placeholder until search is built |
| `/customer/products/:id` | C-05 / B-00a placeholder until product detail is built |
| `/customer/business-upgrade` | B-01 placeholder (customers only) |

The bottom bar is now Home · Categories · Account. Cart, Orders and the quote list join with their tasks.

## Same-day countdown

- `storefront_clock()` returns the server time, `same_day_cutoff` and `holidays` in one call. The app keeps the offset between server and device clocks, so a wrong phone clock doesn't change the promise.
- Before the cut-off on a delivery day: "Order within **4h 35m** for delivery today". It refreshes every 30 seconds.
- From the cut-off (3:00 PM by default): "Today's 3:00 PM cut-off has passed. Order now for delivery tomorrow."
- On or just before a holiday: "Order now for delivery on Tue 10 Nov." (the next day that isn't a holiday).
- C-02 shows the short form, "Delivered today if you order before 3:00 PM".
- Display only. Checkout (F17) decides the delivery day on the server.

## Database

```
supabase/migrations/20261103000100_storefront.sql
  catalog_browse(p_category, p_collection, p_brands, p_min_cents, p_max_cents,
                 p_min_rating, p_in_stock, p_same_day, p_sort, p_limit, p_offset)
      → {rows, total, brands:[{brand,count}], price_bounds:{min,max}|null, all_same_day}
  storefront_clock() → {now, cutoff, holidays}
  indexes for the popular and newest sorts, and collection_items order
supabase/tests/database/15_storefront.test.sql   20 checks (guest, business buyer, staff)
```

- Both functions can be called by `anon` and `authenticated`.
- `p_sort` is `popular` (default, by units sold), `newest`, `price_asc`, `price_desc`, `rating` or `curated` (the collection's own order, used by home rails).
- A category includes all its subcategories. Pages hold at most 60 rows.
- Facets are computed without their own filter: picking a brand keeps the other brands listed, and the price bounds ignore the current price range.

## App

`lib/features/storefront/{data,domain,presentation}`

- **Domain:** `BrowseQuery` (filters, sort and page; any change goes back to page 1; `forBusiness()` drops price filters and sorts), `BrowsePage` / `BrowseItem`, `CategoryTree`, `HomeBanner`, `StoreClock`, `SameDayStatus`, `DeliverTo`.
- **Data:** `StorefrontRepository` (Supabase and offline versions), the same pattern as `ProductReadRepository`.
- **C-01** `home_page.dart`: header (logo, "Deliver to" pill, bell when signed in, search box), banner carousel (swipes, auto-advances every 6 s), `SameDayBanner`, "Shop by category" (4 per row on phones, 8 on wide screens), a rail of best sellers, the business tile, a grid of new arrivals. Pull to refresh. A section with nothing to show is hidden.
- **C-02** `categories_page.dart`: 104 px left rail; the pane shows the category banner (CAT-02) if one is set, the same-day line, subcategory tiles and "Popular in …".
- **C-03** `product_list_page.dart`: chips (Filters with count, Sort, In stock, Under $50, 4★ & up), "N products" and "All ship same day", then a grid of 2 columns on phones and up to 6 on the web. The next page of 20 loads as you near the end. Sold-out cards are marked. Empty, no-match ("Clear filters") and failed ("Try again") states.
- **C-03a** `filter_sheet.dart`: price min/max fields and a range slider, brand checkboxes with counts, rating chips, In stock only and Same-day delivery switches, Reset, and "Show N results", which recounts 300 ms after each change.
- **C-03b** `sort_sheet.dart`: Most popular, Newest, Price low → high, Price high → low, Top rated. Business buyers don't get the two price options.
- **Shared:**
  - `KNetworkImage` (`lib/core/ui/widgets/k_image.dart`): `cached_network_image` with a skeleton while loading and tinted product art as the fallback.
  - `Cutoff` moved from the admin feature to `lib/core/time/cutoff.dart`.
  - `PlaceholderPage.reference` is now optional.
- **Strings:** 72 new `store*` keys in `app_en.arb` and `app_km.arb`.

## Testing it

```
flutter analyze                   # no issues
flutter test --exclude-tags golden  # 386 tests (47 new)
flutter test --tags golden        # 10, unchanged
supabase test db                  # 16 files, 376 checks (20 new)
```

- `test/features/storefront/storefront_domain_test.dart` covers the query rules, JSON parsing, the countdown (before, at and after 3 PM, midnight, holidays, server-clock offset), banner paths, audiences, the category tree and grid columns.
- `test/features/storefront/storefront_pages_test.dart` runs the whole app with a fake storefront and covers:
  - the guest, customer and business homes; the countdown before and after the cut-off and on the server clock
  - banner, category and search navigation; the location pill
  - C-02 rail switching; C-03 chips, the sort and filter sheets, clear filters, scroll paging, an unknown category, retry
  - business price hiding; phone and web layouts
- Tests that used to look for the "Customer home" placeholder now use `storeHome('customer')` from `test/helpers.dart`.

Local stack (run the `restart-app` skill; all passwords are `password123`):

| Step | Result |
|---|---|
| Guest opens the app | Same-day banner "Order by 3 PM, get it today", countdown to 3:00 PM, 8 category shortcuts, Best sellers rail with prices and ≈ KHR, business tile, New arrivals |
| Tap Audio in Categories → see all | "13 products · All ship same day"; In stock leaves 12 (Bluetooth Speaker Mini is sold out) |
| Sort → Price: low to high; Filters → Brand Sonora | Cheapest first; "Show 5 results" |
| `dara@kstore.example` | Pill shows "Home · Toul Kork" |
| `sokha@kstore.example` | Business home: no prices anywhere, quote note instead of the countdown, "Popular for offices", no price chip or price sorts |
| Phone width 390 and a wide browser window | Home and list reflow, up to 6 product columns on the web |

The seed has no product photos, so cards show tinted placeholder art. Upload photos in A-05 to see `KNetworkImage` caching.

## Owner setup (hosted)

1. Apply the new migration: `supabase db push`.
2. Nothing else. Banners, collections and the cut-off are managed in the admin (A-12 / A-14 when those tasks land; `app_settings` until then).

## Decisions and assumptions

- **After the cut-off** the home banner promises tomorrow, or the next non-holiday day. The designs don't show this state; the wording follows the checkout copy in C-07b.
- **Location pill:** guests see "Phnom Penh" and are offered sign-in. Signed-in shoppers can switch between saved addresses for the session. Adding and editing addresses comes with checkout (C-07).
- **Category filter (CAT-04)** is the category you are in, which includes its subcategories. The filter sheet has no category field, as in the design.
- **Business home** uses the B-00 hero content from banners (audience `business`) and the "Popular for offices" collection. The RFQ status tile is not built here; it belongs to the RFQ tasks.
- **Cart and wishlist** aren't shown: cards have no hearts and there is no cart icon or badge until those tasks land.
- **Dependency pin:** `path_provider_foundation` is held at 2.5.1 and `path_provider_android` at 2.2.22, via `dependency_overrides` in `pubspec.yaml`. Newer versions build with FFI/JNI hooks that fail when the Flutter SDK path contains a space (this machine: `C:\Users\chang key\…`). Remove the overrides once that is fixed upstream, or when nobody builds from such a path.
- **Debug role switcher:** in debug builds it now sits at the bottom of the customer home instead of on the placeholder page.
- **Not done here:**
  - search (C-04) and product detail (C-05), which are placeholders
  - wishlist hearts (US-09)
  - an animated shimmer: skeletons are static, to avoid animation timers in every widget test
- **Pre-existing, untouched:** `dart format` also reflowed one line in `test/features/catalog/product_editor_test.dart`.

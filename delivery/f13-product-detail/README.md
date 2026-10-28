# F13 — Product detail

Tapping a product anywhere in the shop (home rails, banners, lists, search) now opens the real product page for guests and customers.

The page shows:
- a photo gallery with a full-screen viewer
- the stock of the selected variant
- the rating, which jumps to the reviews
- the price in USD with KHR underneath
- colour swatches, with sold-out colours disabled
- a delivery card that counts down to today's cut-off on the server clock
- three tabs: Description, Specifications and Reviews
- "You may also like"

"Add to cart" opens the choose-options sheet, which keeps to the per-order limit, then confirms with the "Added to cart" toast.

- Requirements:
  - CAT-01: name, description, images, brand and variants on the page.
  - CAT-05: stock per variant; out-of-stock variants and products can't be added.
- Screens:
  - C-05 Product detail (Description)
  - C-05a Specifications
  - C-05b Reviews
  - C-05c Choose options (sheet)
  - C-05d Added to cart (toast)
  - C-05e Image viewer

## Who sees what

| Viewer | Product page |
|---|---|
| Guest | C-05 with prices. They can add to the cart on this device. The heart sends them to sign in (AUTH-03). |
| Customer | The same, with "to {area}" from their default address on the delivery card. |
| Business buyer | Still the B-00a placeholder. Their page (no prices, Add to quote request) is F26. `product_detail` returns no prices for them anyway (RLS). |

## Routes

- `/customer/products/:id` → C-05. C-05c is a sheet and C-05e a full-screen route on top of it.
- `/customer/cart` → C-06 placeholder (the cart is F16). "View cart" and the cart icon open it.
- `/business/products/:id` → B-00a placeholder (F26).

## Database

```
supabase/migrations/20261105000100_product_detail.sql
  product_detail(p_id)   → {id, slug, name, description, brand, category_id, specs, highlights,
                            max_per_order, same_day, rfq_enabled, rfq_min_qty, rating_avg, rating_count,
                            sold_count, images:[{path, alt, sort, variant_id}],
                            variants:[{id, sku, attributes, sort, price_cents, compare_at_cents,
                                       available, low_stock}],
                            related:[catalog_browse row shape], free_delivery_cents}
                          security invoker: null for drafts and archived products (even for staff),
                          no inactive variants, no prices for business buyers (RLS)
supabase/tests/database/17_product_detail.test.sql   14 checks
supabase/seed.sql      Wireless Headphones Pro gets the design's description, highlights and specs
```

- **Stock per variant:** `available` is on hand minus held, summed over warehouses (`variant_availability`). `low_stock` is F10's per-variant alert level.
- **Related products:** the same category first, then the same brand, most sold first, up to 8.

## App

**`lib/features/storefront/`**

**Domain**
- `product_detail.dart`:
  - `ProductDetail`.
  - `VariantSelection`: picks a variant, disables values with nothing in stock, moves the other choices when a value doesn't combine with them, and works out the most that can be added (`maxQty`).
  - `StockState`: in stock, low (N left), or out.
  - `specRowsFrom`: reads both stored spec shapes.
  - `colourSwatch`.
- `reviews.dart`: the C-05b model.

**Data:** `product_detail_repository.dart`
- `ProductDetailRepository` (Supabase and offline).
- `ReviewsRepository`, which returns nothing until F32.

**Presentation:** `presentation/product_detail/`
- **C-05** `product_detail_page.dart`:
  - Gallery with page dots and a "1 / 5" pill. Choosing a colour moves to that colour's photo when one is linked.
  - Back, Share and the cart with a count badge over the gallery. They turn into a white bar with the title once the gallery scrolls away, as on C-05a/b.
  - Stock line, rating link, price (`KPrice`) and the VAT note.
  - Colour swatches: sold-out colours are faded, crossed through and announced as "Sky, out of stock". Other attributes (size, pack) show as chips.
  - Delivery card.
  - Tabs.
  - Related row.
  - Action bar with the heart and "Add to cart", which shows "· $49.00" on the Specifications and Reviews tabs, as in the design.
- **Delivery card** `pd_widgets.dart`:
  - Before the cut-off: "Get it today · Order within 4h 35m · delivered by 8:00 PM [to Toul Kork]. Free over $50."
  - After the cut-off: "Get it tomorrow" (or on the next day that isn't a holiday).
  - It re-renders every 30 s from the server clock (`storeClockProvider`, as on C-01).
- **C-05a / C-05b tabs** `pd_tabs.dart`:
  - Description collapses to 4 lines with Read more, and shows the highlights as ticks.
  - Specifications puts brand and colours first, then the product's rows and the brand note.
  - Reviews has the summary with bars, filter chips, review cards with photos and K's reply, and "See all N reviews". It shows the empty state until F32 brings the data.
- **C-05c** `choose_options_sheet.dart`:
  - Shows the thumbnail, price with KHR, "N in stock", and chips with colour dots. Sold-out chips have a dashed outline and read "Sky · sold out".
  - The quantity stepper stops at the line limit, with "Max. 5 per order" and "N already in your cart".
  - The cut-off banner, then "Add to cart · $total".
- **C-05d:** `KToast` gained an optional second line (`detail`) for "Wireless Headphones Pro · Black · 1", plus "View cart".
- **C-05e** `image_viewer_page.dart`: ink background, "2 / 5" counter, pinch to zoom, thumbnail strip.

**Cart:** `lib/features/cart/` (minimal; F16 builds the cart)
- `CartRepository` keeps lines (variant, product, quantity) on the device with SharedPreferences, set in `main.dart`.
- `cartProvider` adds lines and keeps each within its limit. `cartCountProvider` drives the badge.
- No prices are stored: checkout prices and checks stock on the server.

**Other changes**
- `KIcons.share` and `KIcons.zoomIn` (from the design SVGs).
- `productArtFor(id, name)` for placeholder art outside a `BrowseItem`.
- `AppRoutes.cart`.
- Strings: 73 new `pd*` keys in `app_en.arb` and `app_km.arb`.

## Testing it

```
flutter analyze        # no issues
flutter test           # 469 tests (45 new)
supabase test db       # 17_product_detail: 14 checks
```

- `test/features/storefront/product_detail_test.dart` (17 tests):
  - parsing, including business buyers without prices
  - images linked to colours
  - option axes
  - selection: start on stock, price and stock follow colour, disabled values, choices that move
  - quantity limits and sold-out products
  - both spec shapes
  - swatches, review shares
- `test/features/cart/cart_test.dart` (6 tests): merging and limits, encoding, device storage, the provider and the count.
- `test/features/storefront/product_detail_page_test.dart` (22 tests):
  - **C-05:**
    - stock, rating, USD and KHR, delivery before and after the cut-off, the address
    - description, highlights and related products
    - White changes price and stock; Sky can't be chosen
    - rating → Reviews
    - sold out, not found, retry, web layout
  - **C-05a/b:** the spec rows and note, the price on the button, the reviews empty state, and summary and cards with a filter.
  - **C-05c/d:**
    - the stepper stops at 5
    - the toast text and the cart badge
    - sheet choices carry back to the page
    - a full line can't be added again
    - View cart opens C-06
  - **C-05e and heart:** the viewer opens and closes; guests are sent to sign in; signed-in shoppers get the "coming soon" toast.
  - **Business buyers:** still see B-00a.

The pgTAP file was run against the local database inside a transaction that was rolled back. The full `supabase test db` run needs the rebuilt database (see below).

Local stack (run the `restart-app` skill; it rebuilds the database because the migration and seed changed; all passwords are `password123`):

| Step | Result |
|---|---|
| Home → Wireless Headphones Pro | "In stock · Only 11 left", 4.6 · 128 reviews, $49.00 ≈ KHR 200,900, Colour: Black, Sky crossed through |
| Before 3 PM | "Get it today · Order within …h …m · delivered by 8:00 PM. Free over $50." After 3 PM: "Get it tomorrow" |
| Tap White | "Only 11 left" goes away (40 in stock); the price stays $49.00 |
| Specifications | Brand Sonora, Model WH-PRO, Colour Black, White, Sky, … 12 months, and the note |
| Reviews | Summary tab count 128; the list shows the empty state until F32 |
| Add to cart → + to 5 | The stepper stops at 5, "Max. 5 per order". Add → toast "Added to cart · Wireless Headphones Pro · Black · 5", badge 5 |
| Add to cart again | "5 already in your cart", "You already have the most you can order." The button is disabled |
| Tap the "1 / 1" pill | Full-screen viewer, Pinch to zoom, close |
| Heart as a guest | Sign-in. As `dara@kstore.example`: "Saving to your wishlist is coming soon." |
| `dara@kstore.example` | The delivery card says "to {area}" from the default address |
| Bluetooth Speaker Mini | "Out of stock", "Sold out" button disabled |
| Running Sneakers Air | Sizes as chips; size 42 shows "Only 3 left" |
| `sokha@kstore.example` → any product | B-00a placeholder |

## Owner setup (hosted)

1. Apply the migration: `supabase db push`.
2. Optional: fill in description, highlights and specs in A-05 for the products you sell. The page shows "No description yet." and "No specifications yet." until then.

## Decisions and assumptions

- **Cart on the device.** Guests may add to the cart (App Flow F3), so F13 keeps cart lines on the device behind `CartRepository`. F16 adds the signed-in cart on the server, syncing, and C-06. The app decides no money or stock here: the quantity limit only shapes the stepper, and checkout re-prices and re-checks stock on the server (F16, F17).
- **Quantity limit:** the smallest of `products.max_per_order`, what is in stock, and 999 (the `cart_items` cap), less what is already in the cart. "Max. N per order" shows only when the product sets a limit.
- **"Only N left":** shown when the variant is at or under its F10 alert level. Out of stock is a red "Out of stock" pill. Neither is in the design; they use the K pill tones.
- **Variants:** colour (`attributes.colour`) is swatches on the page and dot chips in the sheet. Other attributes are chips. Swatch colours come from a small name map (Black, White, Sky, Navy, Olive, Sand, …), with a grey fallback; the name is always shown or announced too.
- **Specifications:** both stored shapes work, the F09 `[{name, value}]` and older `{key: value}`, whose keys become labels (`weight_g` → "Weight g"). Brand and colours come first, as on C-05a.
- **Reviews:** the summary, bars, chips and cards are built and tested with sample data. The real data (with reviewer names, which needs a security-definer read) and Helpful votes are F32. Until then the tab shows the empty state. The rating link and tab count use `products.rating_avg/count`.
- **Share copies the link** ("Link copied"), because there is no share-sheet plugin. It only shows on the web for now; mobile needs a public web domain for links, which isn't set up yet.
- **Delivery card wording:** deliveries end at 8:00 PM and returns are 3 days (market rules); "Free over $X" comes from `app_settings.free_delivery_cents`. Guests see no "to {area}". Products with `same_day = false` say "Delivered in 1–2 days".
- **The "Add to cart" button** on C-05 opens C-05c every time, so the variant and quantity are always confirmed.
- **Riverpod retries a failed read in the background.** The page shows "Couldn't load this… Try again" during those retries instead of the skeleton.
- **Not done here:**
  - reviews data, writing reviews and the wishlist toggle (F32)
  - the server cart and C-06 (F16)
  - B-00a / B-00b for business buyers (F26)
  - sale prices (`compare_at_cents` is read but not shown; the seed has none)
  - the W-03 two-column web layout (the phone layout is centred at 720 px)

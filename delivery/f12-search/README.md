# F12 — Search

Shoppers can search the shop in English or Khmer, with typos. Suggestions appear after 2 characters. Results reuse the product-list filters and sort, with Best match first. A search that finds nothing offers "Did you mean …". Every search is timed in the app and logged on the server.

- Requirement: CAT-03 (keyword search with typo tolerance, Postgres full text and trigram, Khmer and English). Also US-02: results in under 1 s, minor typos still find results, and the empty state suggests categories.
- Screens: C-04 Search (typing), C-04a Search results, C-04b No results.

## How matching works

| Query | What finds it | Example |
|---|---|---|
| English words or word starts | Full text, prefix, stemmed and as typed | "head" → Wireless Headphones Pro; "he" works too (an English stopword) |
| Khmer, or part of any word | Substring of the name, brand and category names | "កាស" → 8 headphones and earbuds; "សំឡេង" (Audio) → its 13 products |
| A small typo (4+ characters) | Trigram word similarity ≥ 0.5, only when the words themselves find nothing | "headphnes", "backpak", "wireles" |
| A heavy typo | Nothing, then C-04b offers the closest catalog word (similarity ≥ 0.3) if it finds products | "hedfones" → "Did you mean **headphones**?" |

- Ranking (Best match) adds the full-text rank (name > brand > category), how close the query is to the name, and a bonus when the name contains or starts with the query. Ties go to best sellers.
- Khmer has no spaces between words, so Khmer is matched as a substring. Trigram typo matching starts at 4 characters: a 3-letter Khmer word otherwise "matches" unrelated names that share two letters.
- Only active products are ever found, even for staff. Business buyers get no prices in results or suggestions (RLS, as in F11).

## Speed (US-02)

Measured on the local stack with 5,000 extra products (`tool/search_benchmark.sql`, rolled back afterwards):

| Query | Server time |
|---|---|
| `headphones` (519 hits) | 47 ms |
| `wireless head` | 25 ms |
| `headphnes` (typo fallback) | 114 ms |
| `កាស` (1,008 hits) | 52 ms |
| `speaker` + In stock + under $50 | 40 ms |
| Suggestions for `he` / `headph` | 30 ms / 29 ms |
| `hedfones` + Did you mean | 80 ms + 14 ms |

Through the local API (HTTP, seed data) results take 10–85 ms. The app times every search with a stopwatch. It logs `Search "…" found N in X ms` in debug builds and flags anything over 1 s. It sends the time to `record_search`, which stores it in `search_log.took_ms` so staff can check p95 on real traffic.

To get these numbers, `catalog_browse` (from F11) now works out the lowest price and the stock in one set-based pass. Before, it ran one lookup per product. Browsing all 5,000 products went from 3,080 ms to 128 ms, so the F11 product list is faster too.

## Database

```
supabase/migrations/20261104000100_search.sql
  product_search            one row per product: weighted tsvector + EN/KM haystack; GIN indexes
                            kept current by triggers on products (name, brand, category) and categories
  search_vocabulary         materialized view: words and 2-word phrases of active names, brands, categories
                            refreshed by statement triggers (not on sold_count or ratings)
  search_matches(q)         → (product_id, relevance); each match arm planned with its values (EXECUTE)
  catalog_browse(…, p_q)    + p_q and p_sort 'relevance' (default when searching)
  catalog_suggest(q)        → {terms:[{term,fuzzy}], scope:{term,category}|null, products:[…]} from 2 chars
  search_did_you_mean(q)    → corrected query, only if it finds products; else null
  popular_categories()      → best-selling active categories (6)
  record_search(q, n, ms)   logs every search; signed-in: recent searches, 20 kept
  search_history            RLS: read and clear your own; written only by record_search
  search_log                RLS: staff read; written only by record_search
  anonymise_account         now also deletes search history and unlinks the log
supabase/tests/database/16_search.test.sql   44 checks
tool/search_benchmark.sql                    the timing run above
```

- The seed now has Khmer names for the products. The clear phone case stays untranslated on purpose.
- `product_search` and `search_vocabulary` can't be read by shoppers. Staff can read `product_search` to understand a ranking.

## App

`lib/features/storefront/`

- **Domain** `search.dart`: `normalizeSearch` (as the server does it), `pushRecent`, `matchRuns` (bolding), `SearchSuggestions`. `BrowseQuery.search` and `BrowseSort.relevance`, which the sort sheet offers only for search results.
- **Data**
  - `search_repository.dart`: Supabase and offline versions.
  - `recent_search_store.dart`: guests' recent searches on the device (SharedPreferences, set in `main.dart`). Signed-in shoppers' searches are kept per account.
- **C-04** `search_page.dart` (typing):
  - Focused box with Clear and Cancel.
  - Suggestions after 2 characters, refreshed 250 ms after typing stops: words with the completion in bold, "headphones in Audio", and up to 3 products with price and category.
  - Recent searches as chips, with Clear (asks first).
  - Popular categories.
- **C-04a** (results):
  - Back and the search box (tap to edit; Cancel returns to the results).
  - Chips: Filters (the C-03a sheet), Sort (Best match first), In stock, and the category chip when searching "in Audio" (tap to drop it).
  - "N results for “…”".
  - List rows on phones and the product grid from 600 px, with "Show N more results" every 20.
- **C-04b** (no results): "No results for “…”", "Did you mean <link>?", the Try this card and popular categories. When filters emptied the list, it shows "No products match" with Clear filters instead.
- **Routes:** `/customer/search` and `/business/search`; `?q=` opens straight on the results (`AppRoutes.search(shell, query: …)`).
- **Strings:** 19 new keys in `app_en.arb` and `app_km.arb`.

## Testing it

```
flutter analyze                     # no issues
flutter test --exclude-tags golden  # 414 tests (28 new)
flutter test --tags golden          # 10, unchanged
supabase test db                    # 17 files, 420 checks (44 new)
```

- `test/features/storefront/search_domain_test.dart`: normalising, recent searches (memory and device), bolding runs, suggestion parsing, the search in `BrowseQuery`, Best match options, the route.
- `test/features/storefront/search_page_test.dart`:
  - typing: suggestions from 2 characters, the scoped and product rows, recent and popular, clearing with confirmation, Cancel
  - results: prices, timing recorded, Khmer, `?q=`, In stock, the sort sheet, Clear filters, the category scope, Show more, editing, back, retry, business buyers without prices, the web grid
  - no results: "hedfones" suggests headphones while typing and on C-04b, and tapping it searches; no suggestion when nothing is close

Local stack (run the `restart-app` skill; all passwords are `password123`):

| Step | Result |
|---|---|
| Home → tap the search box | C-04 with Popular categories (Audio, Sports, Fashion, …) |
| Type `head` | headphones, "headphones in Audio", headset…, and 3 products with prices |
| Search `headphones` | 4 results, Best match first: Wireless Headphones Pro |
| Search `hedfones` | "No results for “hedfones”" · "Did you mean **headphones**?" → tap → 4 results |
| Search `headphnes` | 4 results (typo tolerated) |
| Search `កាស` / `សំឡេង` | 8 headphones and earbuds / the 13 Audio products |
| `dara@kstore.example`, search a few things, sign out and in | Recent searches follow the account; guests keep their own on the device |
| `sokha@kstore.example` | No prices in suggestions or results, "Price on quote · Min. 5", no price sorts |
| A wide browser window | Results as a product grid |

## Owner setup (hosted)

1. Apply the migration: `supabase db push`. It backfills `product_search` and builds the vocabulary from the existing catalog.
2. Nothing else. To check speed on real traffic: `select percentile_cont(0.95) within group (order by took_ms) from search_log where created_at > now() - interval '1 day';`

## Decisions and assumptions

- **Heavy typos don't return results.** C-04b shows "hedfones" with no results and "Did you mean headphones", so a correction is offered rather than applied. Light typos (one letter off, 4+ characters) do return results, which is what US-02 asks for.
- **Typo matching is a fallback.** It only runs when the words themselves find nothing. "wireless head" lists 40 exact hits rather than 500 fuzzy look-alikes, and it is about 5× faster.
- **Suggestions are corrected only from a whole misspelt word:** "hedfones" suggests headphones, but the fragment "hedf" is too far from any catalog word.
- **Recent searches:** stored normalised (lowercase), 8 shown, 20 kept per account. Clearing asks for confirmation (house rule for destructive actions), though the design shows a plain link.
- **No Add button on result rows:** there is no cart until F14. Rows open the product, which is still the C-05 placeholder.
- **Search log:** guest searches are logged with no profile. Nothing rate-limits `record_search` yet. If abuse shows up, add a limit in an Edge Function or the API gateway.
- **Not done here:** synonyms (the PRD risk table mentions them for Khmer), an admin view of the search log (zero-result queries), and a Khmer word segmenter. Substring and trigram matching cover v1.

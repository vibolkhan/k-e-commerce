# F03 — Languages, currency & formatting

Khmer and English with a live switch; money and dates shown the K way. Requirements: INT-03, PAY-05. Screens: S-02, S-08c.

## Language

| Piece | Where |
|---|---|
| Strings | `lib/core/l10n/app_en.arb`, `app_km.arb` → `flutter gen-l10n` (runs on `pub get`) |
| Supported languages, native names, picker order (Khmer first) | `core/l10n/supported_languages.dart` |
| Current choice | `localeControllerProvider` (`core/l10n/locale_controller.dart`); `null` = follow the device |
| Storage | `LocaleStore` (device, `shared_preferences`) and `LocaleAccountSync` (account) in `core/l10n/locale_store.dart` |

- `KApp` watches the controller, so `setLocale()` changes every string on the next frame — no restart.
- **Guests:** the choice is saved on the device.
- **Signed in:** it is also saved to the Supabase auth user's `user_metadata.locale`. On sign-in (or a restored session) the account's language wins; if the account has none, the device choice is uploaded. No table is needed.
- `main.dart` loads `SharedPreferences` before `runApp`, so the first frame is already in the saved language.

### Picker widgets — `features/settings/presentation/`

- `LanguageOptions`: radio group of the languages. It comes in two styles: `cards` (S-02, with glyph badges) and `list` (S-08c, where the language in use shows "Current language").
- `showLanguageSheet(context)`: the S-08c sheet. Nothing changes until **Save**; closing the sheet keeps the current language.
- `LanguageSelectView(onContinue:)`: the S-02 body. Tapping a card switches the language at once, so the screen previews it.

**Left for F06:** mount `LanguageSelectView` on the first-launch route (shown only while no language is saved), and open `showLanguageSheet` from Account › Language. Until then, the placeholder role home has a **Language** button and a sample price.

## Money — `core/money/`

Amounts are **integer US cents incl. VAT**. KHR is display-only: the server decides what is charged, in USD.

| Function | Example |
|---|---|
| `formatUsd(cents)` | `4900` → `$49.00`; `123450` → `$1,234.50`; `-200` → `-$2.00` |
| `usdCentsToKhr(cents, rate)` | `(4900, 4100)` → `200900` |
| `formatKhrAmount(riel)` | `200900` → `200,900` |
| `formatKhr(l10n, cents, rate:)` | `≈ KHR 200,900` (en), `≈ 200,900 រៀល` (km) |
| `KPrice(cents:, size:)` | USD line plus the KHR line, both in tabular figures; reads the rate itself |

- **Rounding:** riel is rounded half away from zero to the nearest **100 riel** (the smallest note). Example: $12.99 → 53,259 → 53,300.
- **Digits:** Latin digits and comma grouping in both languages; only the wording is translated.
- **Business buyers never see retail prices.** Don't use `KPrice` for them; use `KProductCard.business`.

### KHR rate

- `khrRateProvider` reads `SettingsRepository.khrPerUsd()`.
- If the value is missing, ≤ 0, or can't be read, or Supabase isn't configured, it uses `kDefaultKhrRate` = **4,100**.
- `khrRateValueProvider` gives the value to display: the default until the setting loads.

**Contract for F04/F14.** The Supabase repository reads:

```sql
-- app_settings(key text primary key, value jsonb, updated_at timestamptz)
select value from app_settings where key = 'khr_per_usd';   -- e.g. 4100
```

The table needs RLS: readable by `anon` and `authenticated`, writable by admins only, and changes recorded in the audit log. F03 adds no migration because the schema belongs to F04. Until that table exists, the app uses 4,100.

## Dates and times — `core/time/`

Everything is in **Asia/Phnom_Penh**, whatever the device time zone. Cambodia is UTC+7 all year with no daylight saving, so a fixed offset is used instead of a time zone database.

| Function | Example |
|---|---|
| `toPhnomPenh(instant)` | UTC+7 wall-clock time, for display and day maths |
| `phnomPenhDaysBetween(a, b)` | calendar days apart in Phnom Penh |
| `formatShortDate(l10n, t)` | `Thu 22 Oct` |
| `formatDeliveryDay(l10n, t, now:)` | `Today, Thu 22 Oct` / `Tomorrow, Fri 23 Oct` / `Mon 26 Oct` |
| `formatTime(l10n, t)` / `formatByTime(l10n, t)` | `8:00 PM` / `by 8:00 PM` |

Take `now` from `clockProvider` (`ref.read(clockProvider)()`) so tests can freeze time.

The cut-off rule (3:00 PM) is not here: the server decides same-day versus next-day.

## Testing

```
flutter analyze
flutter test
flutter run -d chrome
```

To check the done criteria in the running app:

1. On the customer home, tap **Language**, pick **Khmer**, and tap **Save**. Every string switches at once.
2. Reload the page: the app is still in Khmer.
3. The sample price shows `$49.00` and `≈ KHR 200,900` (`≈ 200,900 រៀល` in Khmer).

Tests:

- `test/core/money/`: formatting, rounding, and the rate fallback.
- `test/core/time/`: today and tomorrow across Phnom Penh midnight, times, and Khmer output.
- `test/core/l10n/`: loading, saving, and account sync.
- `test/core/ui/k_price_test.dart`
- `test/features/settings/`: the live switch through `KApp`, the S-02 preview, semantics, and the 44 px rows.

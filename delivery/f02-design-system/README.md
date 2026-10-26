# F02 — Design system in Flutter

The K design system, coded once in `lib/core/ui`. Every screen is built from these parts.
Sources: `delivery/K_UX-UI_Screens/screens/Main.html` (Brand & foundations), `F02Components.html`, `F03Overlays.html`, `Cmp*Nav.html`, tokens in `k-ui.css`.

```dart
import 'package:k_e_commerce/core/ui/k_ui.dart'; // theme, tokens, icons, widgets
```

## Layout

```
lib/core/ui/
  theme/   k_tokens.dart (KColors, KSpacing, KRadius, KShadows, kMinTap)
           k_typography.dart (KFonts, KTextStyles), k_theme.dart (KTheme extension, context.k)
           app_theme.dart (Material ThemeData built from the tokens)
  icons/   k_icon.dart (KIcon painter), k_icons.dart (61 icons copied from the board SVGs)
  widgets/ one file per family, listed below
  k_ui.dart  barrel
lib/core/domain/statuses.dart  OrderStatus, PaymentStatus, QuoteStatus, ReturnStatus, …
lib/features/design_gallery/   /design-gallery page
assets/fonts/                  Plus Jakarta Sans 400–800, Kantumruy Pro 400–700 (SIL OFL)
```

## Tokens

| Group | Values |
|---|---|
| Colour | primary `#0272B6`, primary ink `#025A91`, brand sky `#0EA5E9` (logo only), ink `#0F172A`, ink2 `#334155`, ink3 `#475569`, muted `#64748B` (on white only), line `#E2E8F0`, line2 `#CBD5E1`, bg `#F8FAFC`, soft `#F1F5F9`; ok / warn / bad + tints; danger fill `#DC2626`; violet |
| Spacing | 4 · 8 · 12 · 16 · 24 · 32 · 48 (`KSpacing.x1…x12`) |
| Radius | 8 tags · 12 inputs/buttons · 14 boxes · 16 cards · 22 dialogs · 24 sheets · pill |
| Shadows | level 1 cards · level 2 floating · level 3 overlays |
| Type | Display 32/40/800 · H1 24/32/800 · H2 20/28/700 · H3 17/24/700 · Body 15/22 · Label 13/18/600 · Small 13/18 · Caption 12/16/500 · Overline 12/16/700 · Price 24/32/800 |

Read them in widgets with `context.k.colors.primary`, `context.k.text.h3`, `context.k.shadow2`. Khmer text uses Kantumruy Pro through `fontFamilyFallback`, glyph by glyph, so mixed copy works in both locales.

## Widgets

| Widget | Notes |
|---|---|
| `KButton` (+ `.tonal/.outline/.ghost/.danger`, `dangerOutline`) | sm 36 / md 48 / lg 56; `loading` + `loadingLabel` ignores taps; `expand`; sm keeps a 44 px tap area |
| `KIconButton` | 44 px; plain/soft/white/outline; `badge`, `dot`; label required |
| `KTextField`, `KTextField.search` | label, `optional`, `prefixText` (+855), `prefixIcon`, `suffix`, `errorText` (replaces `helpText`), multiline |
| `KOtpField` | 6 boxes over one hidden field: paste and SMS autofill work; `error`; `onCompleted` |
| `KChip`, `KSegmented<T>`, `KTabs` | chips with count; segmented control; tabs with counts, `fill` or scrolling |
| `KOptionTile`, `KRadioMark`, `KSwitchRow` | radio cards (payment method), radio mark for sheet rows, switch row |
| `KStatusPill` | `.order/.payment/.quote/.returns/.business/.review/.riderJob` map statuses to tone + localized label as on the Components board; or `KStatusPill(label:, tone:)` |
| `KCard`, `KList`, `KListRow` | outlined / shadow / tint cards; rows with icon tile, subtitle, chevron |
| `KQtyStepper`, `KStars`, `KProgressBar` | stepper bounded by min/max (the server still validates stock) |
| `KProductCard`, `KProductCard.business`, `KProductArt` | the business variant has **no price parameter**: it shows only "Price on quote" and the minimum quantity |
| `KTimeline` | steps done / now / todo / bad |
| `KEmptyState`, `KBanner` (`.rich`) | banners info / warn / bad / ok |
| `KToast` + `showKToast()` | bottom, 4 s, one at a time, announced to screen readers |
| `KBottomSheet` + `showKBottomSheet()` | grab handle, title, close |
| `KConfirmDialog` + `showKConfirm()` | neutral / destructive, optional ghost alternative; resolves `true` only on confirm |
| `KBlockingProgress` | spinner card for "Confirming your payment…" |
| `KBottomNav.customer/.guest/.business/.rider/.admin` | board layouts; badge counts folded into the accessible label |
| `KAppBar` | 56 px, auto back button, centred or left title, actions |
| `KLogo` (`.white`, `.onInk`), `KAppIcon` | K mark ≥ 20 px |
| `KBadge`, `KDot`, `KSpinner`, `KSkeleton`, `KAvatar`, `KOverline` | small parts |

Rules carried into the components: confirm before money, data loss or cancelling (`showKConfirm`, destructive tone in red, the action names what happens); tap targets ≥ 44 px; status always in words; every component-owned string is in `app_en.arb` / `app_km.arb`.

## Gallery

`/design-gallery` shows every widget, laid out like the boards. It is registered only when `APP_ENV` is not `prod`, isn't linked anywhere, and opens for any role:

```
flutter run -d chrome --dart-define-from-file=config/env.json
# then open http://localhost:<port>/#/design-gallery
```

Its sample copy (product names, prices) is dev-only sample data and isn't in the ARB files.

## Tests

```
flutter analyze
flutter test                                   # everything, incl. goldens
flutter test --exclude-tags golden             # what CI runs
flutter test --update-goldens --tags golden    # after an intended visual change
```

- `test/core/ui/k_theme_test.dart`: theme wiring, type scale, WCAG contrast of token pairs, status → tone/label mappings (en + km).
- `test/core/ui/k_widgets_test.dart`: behaviour and semantics (loading, disabled, OTP paste, qty bounds, business card never prices, nav layouts, confirm/sheet/toast).
- `test/core/ui/k_goldens_test.dart` and `test/features/design_gallery/design_gallery_test.dart`: goldens at 390 px and the full gallery at 1440 px.
- `test/flutter_test_config.dart` loads the bundled fonts and compares goldens with 0.5 % tolerance. Goldens are made on Windows; Linux renders text differently, so CI skips the `golden` tag.

## Not in this task

- Map and KHQR placeholders from the Components board, plus push / in-app notification cards from the Overlays board. These come with tracking, payment and notification tasks.
- Admin sidebar/top bar and web header/footer (`CmpAdmin*`, `CmpWeb*`). These come with the admin and web shell tasks.
- Dark theme. `KTheme`/`KPalette` are ready for a second palette.
- Money formatting. `KProductCard` takes preformatted strings until a shared money formatter exists.

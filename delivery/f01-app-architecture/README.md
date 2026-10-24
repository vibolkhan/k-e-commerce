# F01 — App architecture & project setup

The skeleton every later task plugs into. Reference: PRD §8.

## Layout

```
lib/
  main.dart            reads AppConfig, bootstraps services, runApp(ProviderScope(KApp))
  app.dart             MaterialApp.router: theme, localizations, router
  core/
    config/            AppConfig (env + Supabase keys), bootstrap(), appConfigProvider
    router/            AppRoutes, AppRole + currentRoleProvider, routerProvider (role guard)
    ui/                shared UI — pages/ (loading, error), theme/ (placeholder until F02)
    utils/             log() — use instead of print
    l10n/              app_en.arb, app_km.arb → generated/ (gitignored, built on pub get)
  features/<feature>/{data,domain,presentation}
    shell/presentation placeholder home per role
```

## Routing and roles

- Roles: `customer`, `business`, `rider`, `admin`, each with its own shell at `/customer`, `/business`, `/rider`, `/admin`.
- `/` redirects to the current role's home. Opening another role's shell (or anything under it) redirects to `/forbidden`. Unknown paths show the not-found page.
- The rule lives in `roleRedirect()` in `lib/core/router/app_router.dart`.
- `currentRoleProvider` is a stub defaulting to `customer`; F05/F06 will set it from the Supabase session. In debug builds each placeholder home has a role switcher.
- **Adding a route:** add the path to `AppRoutes`, put routes for a role's screens under that role's path (e.g. `/customer/cart`) so the guard covers them, and register them in `routerProvider`.

## Environments

Config comes from `--dart-define`s; no secrets are committed.

| Define | Values | Default |
|---|---|---|
| `APP_ENV` | `dev`, `staging`, `prod` | `dev` |
| `SUPABASE_URL` | project URL | empty |
| `SUPABASE_ANON_KEY` | anon / publishable key (never the service-role key) | empty |

```
cp config/env.example.json config/dev.json   # fill in; config/*.json is gitignored
flutter run --dart-define-from-file=config/dev.json
```

Without Supabase keys the app runs offline and shows a notice. In `prod`, missing keys stop startup.

## Lints and CI

- `analysis_options.yaml`: `flutter_lints` + `prefer_const_*`, `avoid_print`, `prefer_single_quotes`, `unawaited_futures`, `directives_ordering`, `always_declare_return_types`; strict casts and raw types.
- `.github/workflows/ci.yml` runs on PRs and pushes to `main`: `flutter pub get` → `dart format` check → `flutter analyze` → `flutter test` (Flutter 3.41.6).

## Testing

```
flutter analyze
flutter test
flutter run -d chrome       # check: customer home, role switcher, /#/nope shows not found
```

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`k_e_commerce` is a Flutter app (Dart SDK ^3.11.4) that has only just been scaffolded. `lib/main.dart` is still the default counter template and `test/widget_test.dart` is the default counter smoke test. There's no app architecture, state management, routing or backend integration yet, so the first feature work will need to establish them. Platform folders exist for android, ios, web, macos, linux and windows.

## Delivery output

Save every output file Claude produces (docs, plans, reports, exports and other deliverables) in `delivery/`, inside a subfolder named after the feature it belongs to, e.g. `delivery/<feature-name>/`. Create the feature folder if it doesn't exist yet. App source code still goes in `lib/` and `test/` as usual.

Branching: work happens on `dev`. PRs target `main`.

## Commands

- Install deps: `flutter pub get`
- Run: `flutter run` (pick a device with `-d <device-id>`; list devices with `flutter devices`)
- Analyze/lint: `flutter analyze` (rules come from `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`)
- Format: `dart format .`
- All tests: `flutter test`
- Single test file: `flutter test test/widget_test.dart`
- Single test by name: `flutter test --plain-name "<test description>"`
- Build: `flutter build apk` / `flutter build ios` / `flutter build web`

## Notes

- When you replace the counter template in `lib/main.dart`, update or replace `test/widget_test.dart` too. It asserts on the counter UI (`MyApp`, '0'/'1' text, `Icons.add`) and will fail otherwise.
- `publish_to: 'none'`: this is a private app, not a pub.dev package.

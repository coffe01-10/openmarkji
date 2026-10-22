# Repository Guidelines

## Project Structure & Module Organization

OpenMarkji is an offline-first Flutter flashcard app. `lib/main.dart` initializes the app; `lib/ui/` contains screens, themes, and shared controls. Several screen files are parts of `lib/ui/app.dart`, so preserve their library structure. `lib/data/app_store.dart` owns active persistence and study-session behavior, backed by Drift/SQLite. `lib/domain/` defines entities, `lib/algorithms/` implements MMX scheduling, and `lib/content/` handles Markji parsing and imports. Legacy demos in `bin/`, `lib/models/`, and `lib/services/scheduler.dart` are not the active application stack.

Tests live in `test/`; import examples and documentation are in `examples/` and `docs/`. Platform integration lives in `android/`, `web/`, `windows/`, and `linux/`. Glass shaders are in `shaders/`; adapted FlClash components and notices are in `lib/ui/flclash/` and `third_party/FlClash/`. Do not edit generated `build/` output.

## Build, Test, and Development Commands

- `flutter pub get`: install locked dependencies.
- `dart format lib test`: format Dart sources and tests.
- `flutter analyze`: run configured Flutter lints and static analysis.
- `flutter test --no-pub`: run the test suite.
- `flutter test test/ui_test.dart --no-pub`: run focused widget tests.
- `flutter run -d web-server --web-port 5127 --no-pub`: start local development.
- `flutter build web --no-pub --no-web-resources-cdn`, then `node tool/preview.mjs`: serve the built app; `/phone` provides a phone preview.
- `./tool/build_android.ps1`: build Android using the Windows path workaround.

## Coding Style & Naming Conventions

Use Dart formatting, two-space indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `flutter_lints`. Keep scheduling and persistence logic out of widgets. Preserve stored rating codes and the visible order: 认识、模糊、忘记.

## UI Style

Keep UI styling aligned with FlClash: surface hierarchy, superellipse corners, grouped settings, typography, spacing, liquid-glass materials, and motion. Reuse `lib/ui/flclash/` and shared controls in `lib/ui/design.dart`. Apply appearance preferences consistently across new screens and controls; preserve light/dark themes and reduced-motion support.

## Testing Guidelines

Use `flutter_test` and name files `*_test.dart`. Add focused regressions for scheduling, transactions, imports, backups, and changed interactions. Independent practice and same-day relearning must not alter long-term scheduling. Check narrow layouts and large text for UI changes. Use the built-in browser by default, rather than Playwright. No numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

History uses concise imperative subjects, such as `Improve editor layout, formatting, and interaction`; Conventional Commit prefixes are not required. Keep commits focused. PR descriptions should explain behavior changes, reference relevant issues, report validation and environment limitations, and include screenshots for UI changes. Preserve FlClash licenses, attribution, and modification notices.

## Agent Working Practices

Prefer Chinese communication. Remove temporary files immediately after use. Add checks only for a demonstrated bug or a concrete, named risk. Report missing tools or credentials and continue unaffected work.

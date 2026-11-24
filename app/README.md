# My reader: app

Flutter app and packages in a pub workspace (no melos).

```
app/            the application (macOS for now; Android after MVP)
packages/
  core/         pure Dart: domain, ports, use cases (no Flutter)
  core_testing/ fakes and contract tests
  reader_api/   reader engine contract (Flutter)
  storage_drift/ SQLite storage
```

## Requirements

Flutter 3.50.1 / Dart 3.14.0, Xcode and CocoaPods for the macOS build.

## Build and run

```sh
cd app            # this directory (workspace root)
flutter pub get   # resolves the whole workspace
cd app && flutter run -d macos
flutter build macos
```

### Demo app

Real screens over in-memory demo data: a short book, translations, levels. Nothing is read from or written to the app's data. Scenarios are in `app/lib/demo/scenarios.dart`.

```sh
cd app && flutter run -d macos -t lib/main_demo.dart                                   # list of scenarios
cd app && flutter run -d macos -t lib/main_demo.dart --dart-define=SCENARIO=lookup_word # one scenario
```

## Checks

```sh
scripts/check.sh
```

It runs `dart format --set-exit-if-changed .`, `dart analyze --fatal-infos`, the import rules check
(`dart run tool/check_imports.dart`, tested by `dart test tool/test`) and the tests of every package
(`dart test` for pure Dart, `flutter test` for Flutter packages). Run one package alone, for example:

```sh
cd packages/core && dart test
```

## Import rules

`tool/check_imports.dart` reads the `workspace:` list of `pubspec.yaml` and checks the dependencies of every
package, so a new package is covered without editing the script. The kind of a package comes from its directory:

| Directory | Kind | May depend on (workspace) |
|---|---|---|
| `app` | app | anything |
| `packages/core` | core | nothing; no Flutter, drift, sqlite3, http and similar |
| `packages/core_testing` | fakes | core |
| `packages/reader_api` | reader contract | core |
| `packages/reader_*` | renderer | core, reader_api |
| `packages/features/*` | feature | core, reader_api |
| any other `packages/*` | adapter | core |

`core_testing` is allowed in `dev_dependencies` of adapters and features, never in `dependencies`.
`dependency_overrides` are allowed only in `app`. Sources of `core` must not import `dart:ui` or `package:flutter`.
A directory outside this table makes the check fail: add it to `kindOfPath` first.

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

## Checks

```sh
scripts/check.sh
```

It runs `dart format --set-exit-if-changed .`, `dart analyze --fatal-infos` and the tests of every package
(`dart test` for pure Dart, `flutter test` for Flutter packages). Run one package alone, for example:

```sh
cd packages/core && dart test
```

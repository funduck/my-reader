#!/usr/bin/env bash
# Checks for the app/ workspace: format, analyze, import rules, tests of every package.
set -euo pipefail

cd "$(dirname "$0")/.."

dart pub get
dart format --set-exit-if-changed .
dart analyze --fatal-infos

# Dependency rules between packages (docs/Architecture-app.md, section 1),
# then the tests of the rule checker itself.
dart run tool/check_imports.dart
dart test tool/test

# Pure Dart packages use `dart test`, Flutter packages use `flutter test`.
# Packages are found by pubspec.yaml, so features/* are covered too.
for pubspec in app/pubspec.yaml packages/*/pubspec.yaml packages/features/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  dir="$(dirname "$pubspec")"
  [ -d "$dir/test" ] || continue
  if grep -q '^  flutter:' "$pubspec"; then
    (cd "$dir" && flutter test)
  else
    (cd "$dir" && dart test)
  fi
done

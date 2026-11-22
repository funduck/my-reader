#!/usr/bin/env bash
# Minimal check for the app/ workspace: format, analyze, tests of every package.
# T-002 extends this script (import rules etc).
set -euo pipefail

cd "$(dirname "$0")/.."

dart pub get
dart format --set-exit-if-changed .
dart analyze --fatal-infos

# Pure Dart packages use `dart test`, Flutter packages use `flutter test`.
for dir in app packages/*; do
  [ -d "$dir/test" ] || continue
  if grep -q '^  flutter:' "$dir/pubspec.yaml"; then
    (cd "$dir" && flutter test)
  else
    (cd "$dir" && dart test)
  fi
done

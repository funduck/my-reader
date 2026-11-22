#!/usr/bin/env bash
# Checks for the app/ workspace: format, analyze, import rules, tests.
#
#   scripts/check.sh                      every package (before hand-off)
#   scripts/check.sh --package <dir>      one package, e.g. packages/text_en
#
# <dir> is relative to app/ (a leading "app/" is accepted). Test output shows
# failures only.
set -euo pipefail

cd "$(dirname "$0")/.."

package=""
if [ "${1:-}" = "--package" ]; then
  package="${2:?usage: check.sh --package <dir>}"
  package="${package#app/}"
  package="${package%/}"
  [ -f "$package/pubspec.yaml" ] || { echo "no pubspec.yaml in $package" >&2; exit 2; }
fi

dart pub get >/dev/null

run_tests() {
  local dir="$1"
  [ -d "$dir/test" ] || return 0
  echo "== tests: $dir"
  # Pure Dart packages use `dart test`, Flutter packages use `flutter test`.
  if grep -q '^  flutter:' "$dir/pubspec.yaml"; then
    (cd "$dir" && flutter test --reporter failures-only)
  else
    (cd "$dir" && dart test --reporter failures-only)
  fi
}

if [ -n "$package" ]; then
  dart format --set-exit-if-changed "$package"
  dart analyze --fatal-infos "$package"
  dart run tool/check_imports.dart
  run_tests "$package"
  exit 0
fi

dart format --set-exit-if-changed .
dart analyze --fatal-infos

# Dependency rules between packages (docs/Architecture-app.md, section 1),
# then the tests of the rule checker itself.
dart run tool/check_imports.dart
(dart test --reporter failures-only tool/test)

# Packages are found by pubspec.yaml, so features/* are covered too.
for pubspec in app/pubspec.yaml packages/*/pubspec.yaml packages/features/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  run_tests "$(dirname "$pubspec")"
done

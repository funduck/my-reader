#!/usr/bin/env bash
# Stop: if .dart files under app/ changed, run the app checks before Claude
# finishes. On failure Claude gets the output and keeps working (exit 2).
# Runs once per stop: a repeated stop (stop_hook_active) is let through.
set -u

input=$(cat)
[ "$(echo "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -d app ] || exit 0
git status --porcelain -uall -- app 2>/dev/null | grep -q '\.dart$' || exit 0
command -v dart >/dev/null 2>&1 || exit 0

if [ -x app/scripts/check.sh ]; then
  what="app/scripts/check.sh"
  out=$(app/scripts/check.sh 2>&1)
else
  what="dart analyze --fatal-infos (app/scripts/check.sh not found)"
  out=$(cd app && dart analyze --fatal-infos 2>&1)
fi
rc=$?

if [ $rc -ne 0 ]; then
  {
    echo "Checks failed: $what. The task is not done until they pass:"
    echo "$out" | tail -n 60
  } >&2
  exit 2
fi
exit 0

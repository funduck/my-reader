#!/usr/bin/env bash
# PostToolUse (Edit|Write): format the edited .dart file and analyze it.
# Analyzer issues go back to Claude (exit 2) so it fixes them right away.
set -u

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
case "$f" in
  *.g.dart | *.freezed.dart) exit 0 ;;
  *.dart) ;;
  *) exit 0 ;;
esac
[ -f "$f" ] || exit 0
command -v dart >/dev/null 2>&1 || exit 0

dart format "$f" >/dev/null 2>&1

if ! out=$(dart analyze --fatal-infos "$f" 2>&1); then
  {
    echo "dart analyze found issues in $f. Fix them before moving on:"
    echo "$out" | grep -vE '^(Analyzing|No issues found)' | head -n 40
  } >&2
  exit 2
fi
exit 0

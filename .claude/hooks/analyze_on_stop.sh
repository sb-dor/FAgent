#!/bin/bash
# Stop: when .dart files have uncommitted changes, run `flutter analyze` and send any
# issues back to Claude (exit 2). stop_hook_active prevents a second block in a row.
input=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ] && exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
git status --porcelain -- '*.dart' | grep -q . || exit 0
out=$(flutter analyze --no-pub 2>&1) && exit 0
{
  echo "flutter analyze found issues; fix them before finishing:"
  grep -E '^ *(error|warning|info) •' <<<"$out" || echo "$out"
} >&2
exit 2

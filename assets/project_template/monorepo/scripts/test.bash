#!/bin/bash
# Run the tests of every member (apps/*, packages/*) that has a test/ folder. Flutter members run
# with coverage (coverage/lcov.info) and a JSON report (reports/tests.json) in their own folder.
set -euo pipefail

for member in apps/*/ packages/*/; do
  [ -f "${member}pubspec.yaml" ] || continue
  [ -d "${member}test" ] || continue
  echo "==> ${member}"
  if grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter' "${member}pubspec.yaml"; then
    (cd "$member" && flutter test --no-pub --coverage --file-reporter json:reports/tests.json "$@")
  else
    (cd "$member" && dart test "$@")
  fi
done

#!/bin/bash
# Format lib/ and test/ of every member (apps/*, packages/*), skipping generated files
# (*.g.dart, *.freezed.dart, ...). The line length comes from formatter.page_width in
# analysis_options.yaml.
set -euo pipefail

for member in apps/*/ packages/*/; do
  [ -f "${member}pubspec.yaml" ] || continue
  for folder in lib test; do
    [ -d "${member}${folder}" ] || continue
    find "${member}${folder}" -name '*.dart' ! -name '*.*.dart' -exec dart format {} +
  done
done

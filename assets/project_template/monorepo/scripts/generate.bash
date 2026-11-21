#!/bin/bash
# Generate the localizations and the build_runner code (freezed, drift, ...) of every member, then
# format the result.
set -euo pipefail

flutter pub get

uses_build_runner=false
for member in apps/*/ packages/*/; do
  [ -f "${member}pubspec.yaml" ] || continue
  if [ -f "${member}l10n.yaml" ]; then
    (cd "$member" && flutter gen-l10n)
  fi
  if grep -q build_runner "${member}pubspec.yaml"; then
    uses_build_runner=true
  fi
done

if [ "$uses_build_runner" = true ]; then
  dart run build_runner build --workspace --delete-conflicting-outputs
fi

for member in apps/*/ packages/*/; do
  [ -f "${member}pubspec.yaml" ] || continue
  for folder in lib test; do
    if [ -d "${member}${folder}" ]; then
      dart format "${member}${folder}"
    fi
  done
done

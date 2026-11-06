#!/bin/bash
# Generate the localizations and the build_runner code (freezed, drift, ...), then format the result.
set -euo pipefail

flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
dart format lib test

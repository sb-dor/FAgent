#!/bin/bash
# Format lib/ and test/, skipping generated files (*.g.dart, *.freezed.dart, ...). The line length
# comes from formatter.page_width in analysis_options.yaml.
set -euo pipefail

find lib test -name '*.dart' ! -name '*.*.dart' -exec dart format {} +

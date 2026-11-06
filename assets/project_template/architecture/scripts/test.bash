#!/bin/bash
# Run the tests with coverage (coverage/lcov.info) and a JSON report (reports/tests.json) for CI.
set -euo pipefail

flutter test --no-pub --coverage --file-reporter json:reports/tests.json "$@"

#!/bin/bash
# Analyze every member of the workspace from the root: infos count as failures, as in CI.
set -euo pipefail

flutter analyze --no-pub

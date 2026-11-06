#!/bin/bash
# Analyze the project: infos count as failures, as in CI.
set -euo pipefail

flutter analyze --no-pub

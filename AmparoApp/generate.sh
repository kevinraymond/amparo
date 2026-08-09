#!/usr/bin/env bash
# Generates Amparo.xcodeproj. First run creates project-local.yml (gitignored)
# from the example — put your DEVELOPMENT_TEAM there for device builds.
set -euo pipefail
cd "$(dirname "$0")"
[ -f project-local.yml ] || cp project-local.example.yml project-local.yml
exec xcodegen "$@"

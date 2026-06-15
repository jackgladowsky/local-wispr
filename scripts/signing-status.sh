#!/usr/bin/env bash
set -euo pipefail

APP="${1:-$HOME/Applications/Local Wispr.app}"

echo "Available code signing identities:"
security find-identity -v -p codesigning || true

echo
echo "Current app signature:"
if [[ -d "$APP" ]]; then
    codesign -dv --verbose=4 "$APP" 2>&1 | sed -n '1,80p'
else
    echo "App not found: $APP"
fi

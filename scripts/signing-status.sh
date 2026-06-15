#!/usr/bin/env bash
set -euo pipefail

APP="${1:-$HOME/Applications/Local Wispr.app}"
HELPER="${2:-$HOME/Applications/Local Wispr Paste Helper.app}"

print_signature() {
    local label="$1"
    local app="$2"

    echo
    echo "$label signature:"
    if [[ -d "$app" ]]; then
        codesign -dv --verbose=4 "$app" 2>&1 | sed -n '1,80p'
    else
        echo "App not found: $app"
    fi
}

echo "Available code signing identities:"
security find-identity -v -p codesigning || true

print_signature "Main app" "$APP"
print_signature "Paste helper" "$HELPER"

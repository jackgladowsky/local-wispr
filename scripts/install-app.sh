#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/dist/Local Wispr.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Local Wispr.app"

cd "$ROOT_DIR"

if [[ ! -d "$BUILT_APP" ]]; then
    "$ROOT_DIR/scripts/build-app.sh" >/dev/null
fi

mkdir -p "$INSTALL_DIR"

if pgrep -x LocalWispr >/dev/null 2>&1; then
    pkill -x LocalWispr || true
    sleep 0.5
fi

if [[ -d "$INSTALLED_APP" ]]; then
    rm -rf "$INSTALLED_APP/Contents"
    mkdir -p "$INSTALLED_APP"
    ditto "$BUILT_APP/Contents" "$INSTALLED_APP/Contents"
else
    ditto "$BUILT_APP" "$INSTALLED_APP"
fi

codesign --verify --deep --strict "$INSTALLED_APP"
open -n "$INSTALLED_APP"

echo "$INSTALLED_APP"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/dist/Local Wispr.app"
BUILT_HELPER="$ROOT_DIR/dist/Local Wispr Paste Helper.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Local Wispr.app"
INSTALLED_HELPER="$INSTALL_DIR/Local Wispr Paste Helper.app"

cd "$ROOT_DIR"

if [[ ! -d "$BUILT_APP" || ! -d "$BUILT_HELPER" ]]; then
    "$ROOT_DIR/scripts/build-app.sh" >/dev/null
fi

mkdir -p "$INSTALL_DIR"

if pgrep -x LocalWispr >/dev/null 2>&1; then
    pkill -x LocalWispr || true
    sleep 0.5
fi

if pgrep -x LocalWisprPasteHelper >/dev/null 2>&1; then
    pkill -x LocalWisprPasteHelper || true
    sleep 0.2
fi

if [[ -d "$INSTALLED_APP" ]]; then
    rm -rf "$INSTALLED_APP/Contents"
    mkdir -p "$INSTALLED_APP"
    ditto "$BUILT_APP/Contents" "$INSTALLED_APP/Contents"
else
    ditto "$BUILT_APP" "$INSTALLED_APP"
fi

if [[ -d "$INSTALLED_HELPER" && "${LOCAL_WISPR_UPDATE_HELPER:-0}" != "1" ]]; then
    echo "Keeping existing paste helper for stable Accessibility trust: $INSTALLED_HELPER" >&2
else
    if [[ -d "$INSTALLED_HELPER" ]]; then
        rm -rf "$INSTALLED_HELPER/Contents"
        mkdir -p "$INSTALLED_HELPER"
        ditto "$BUILT_HELPER/Contents" "$INSTALLED_HELPER/Contents"
    else
        ditto "$BUILT_HELPER" "$INSTALLED_HELPER"
    fi
fi

codesign --verify --deep --strict "$INSTALLED_HELPER"
codesign --verify --deep --strict "$INSTALLED_APP"
open -n "$INSTALLED_APP"

echo "$INSTALLED_APP"
echo "$INSTALLED_HELPER"

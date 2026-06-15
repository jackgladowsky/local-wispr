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

bundle_version() {
    local app="$1"
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || echo 0
}

install_bundle_contents() {
    local source_app="$1"
    local target_app="$2"

    if [[ -d "$target_app" ]]; then
        rm -rf "$target_app/Contents"
        mkdir -p "$target_app"
        ditto "$source_app/Contents" "$target_app/Contents"
    else
        ditto "$source_app" "$target_app"
    fi
}

install_bundle_contents "$BUILT_APP" "$INSTALLED_APP"

BUILT_HELPER_VERSION="$(bundle_version "$BUILT_HELPER")"
INSTALLED_HELPER_VERSION="$(bundle_version "$INSTALLED_HELPER")"

if [[ -d "$INSTALLED_HELPER" \
    && "${LOCAL_WISPR_UPDATE_HELPER:-0}" != "1" \
    && "$INSTALLED_HELPER_VERSION" -ge "$BUILT_HELPER_VERSION" ]]; then
    echo "Keeping existing paste helper for stable Accessibility trust: $INSTALLED_HELPER" >&2
else
    if [[ -d "$INSTALLED_HELPER" && "${LOCAL_WISPR_UPDATE_HELPER:-0}" != "1" ]]; then
        echo "Updating paste helper from version $INSTALLED_HELPER_VERSION to $BUILT_HELPER_VERSION." >&2
        echo "You may need to re-approve Local Wispr Paste Helper in Accessibility." >&2
    fi
    install_bundle_contents "$BUILT_HELPER" "$INSTALLED_HELPER"
fi

codesign --verify --deep --strict "$INSTALLED_HELPER"
codesign --verify --deep --strict "$INSTALLED_APP"
open -n "$INSTALLED_APP"

echo "$INSTALLED_APP"
echo "$INSTALLED_HELPER"

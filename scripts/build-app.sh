#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Local Wispr.app"
HELPER_APP_DIR="$ROOT_DIR/dist/Local Wispr Paste Helper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPER_CONTENTS_DIR="$HELPER_APP_DIR/Contents"
HELPER_MACOS_DIR="$HELPER_CONTENTS_DIR/MacOS"
HELPER_RESOURCES_DIR="$HELPER_CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$HELPER_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
mkdir -p "$HELPER_MACOS_DIR" "$HELPER_RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/LocalWispr" "$MACOS_DIR/LocalWispr"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/LocalWispr"

cp "$ROOT_DIR/.build/release/LocalWisprPasteHelper" "$HELPER_MACOS_DIR/LocalWisprPasteHelper"
cp "$ROOT_DIR/Packaging/PasteHelperInfo.plist" "$HELPER_CONTENTS_DIR/Info.plist"
chmod +x "$HELPER_MACOS_DIR/LocalWisprPasteHelper"

if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${LOCAL_WISPR_CODESIGN_IDENTITY:-}"

    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="$(
            security find-identity -v -p codesigning 2>/dev/null \
                | awk -F '"' '/"/ { print $2; exit }'
        )"
    fi

    sign_app() {
        local app="$1"

        if [[ -n "$SIGN_IDENTITY" ]]; then
            echo "Signing $(basename "$app") with identity: $SIGN_IDENTITY" >&2
            codesign --force --deep --sign "$SIGN_IDENTITY" "$app" >/dev/null
        else
            echo "Signing $(basename "$app") ad-hoc. Accessibility trust may need reset after rebuilds." >&2
            codesign --force --deep --sign - "$app" >/dev/null
        fi
    }

    sign_app "$HELPER_APP_DIR"
    sign_app "$APP_DIR"
fi

echo "$APP_DIR"
echo "$HELPER_APP_DIR"

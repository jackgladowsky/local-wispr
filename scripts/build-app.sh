#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Local Wispr.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/LocalWispr" "$MACOS_DIR/LocalWispr"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/LocalWispr"

if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${LOCAL_WISPR_CODESIGN_IDENTITY:-}"

    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="$(
            security find-identity -v -p codesigning 2>/dev/null \
                | awk -F '"' '/"/ { print $2; exit }'
        )"
    fi

    if [[ -n "$SIGN_IDENTITY" ]]; then
        echo "Signing with identity: $SIGN_IDENTITY" >&2
        codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
    else
        echo "Signing ad-hoc. Accessibility trust may need reset after rebuilds." >&2
        codesign --force --deep --sign - "$APP_DIR" >/dev/null
    fi
fi

echo "$APP_DIR"

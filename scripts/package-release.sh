#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="${LOCAL_WISPR_RELEASE_DIR:-$DIST_DIR/release}"
APP_DIR="$DIST_DIR/Local Wispr.app"
HELPER_APP_DIR="$DIST_DIR/Local Wispr Paste Helper.app"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"

cd "$ROOT_DIR"

plist_value() {
    local key="$1"
    /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST"
}

SOURCE_VERSION="$(plist_value CFBundleShortVersionString)"
VERSION="${LOCAL_WISPR_RELEASE_VERSION:-$SOURCE_VERSION}"
VERSION="${VERSION#v}"
PLIST_VERSION="${VERSION%%[-+]*}"
BUILD_NUMBER="${LOCAL_WISPR_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

if [[ -z "$VERSION" || -z "$PLIST_VERSION" ]]; then
    echo "Release version is empty" >&2
    exit 1
fi

if [[ "${LOCAL_WISPR_SKIP_BUILD:-0}" != "1" ]]; then
    LOCAL_WISPR_VERSION="$PLIST_VERSION" \
    LOCAL_WISPR_BUILD_NUMBER="$BUILD_NUMBER" \
        "$ROOT_DIR/scripts/build-app.sh" >/dev/null
fi

for app in "$APP_DIR" "$HELPER_APP_DIR"; do
    if [[ ! -d "$app" ]]; then
        echo "Missing built app bundle: $app" >&2
        echo "Run scripts/build-app.sh first or omit LOCAL_WISPR_SKIP_BUILD=1." >&2
        exit 1
    fi

    codesign --verify --deep --strict "$app"
done

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

STAGE_PARENT="$(mktemp -d)"
trap 'rm -rf "$STAGE_PARENT"' EXIT
STAGE_DIR="$STAGE_PARENT/Local Wispr $VERSION"
mkdir -p "$STAGE_DIR"

ditto "$APP_DIR" "$STAGE_DIR/Local Wispr.app"
ditto "$HELPER_APP_DIR" "$STAGE_DIR/Local Wispr Paste Helper.app"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$STAGE_DIR/README.txt" <<EOF
Local Wispr $VERSION

Install:
1. Drag "Local Wispr.app" and "Local Wispr Paste Helper.app" into Applications.
2. Launch Local Wispr from Applications.
3. Complete Microphone and Accessibility permissions from Settings.

For development installs that preserve the paste helper across rebuilds, use scripts/install-app.sh from a source checkout.
EOF

"$ROOT_DIR/scripts/check-release-artifacts.sh" "$STAGE_DIR" >/dev/null

DMG_PATH="$RELEASE_DIR/LocalWispr-$VERSION-macOS.dmg"
ZIP_PATH="$RELEASE_DIR/LocalWispr-$VERSION-macOS.zip"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"

hdiutil create \
    -volname "Local Wispr $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$ZIP_PATH"

if [[ -n "${LOCAL_WISPR_CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --sign "$LOCAL_WISPR_CODESIGN_IDENTITY" "$DMG_PATH"
fi

(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"
)

cat <<EOF
Release assets created in $RELEASE_DIR:
$DMG_PATH
$ZIP_PATH
$CHECKSUM_PATH
EOF

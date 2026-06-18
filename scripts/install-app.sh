#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$ROOT_DIR/dist/Local Wispr.app"
BUILT_HELPER="$ROOT_DIR/dist/Local Wispr Paste Helper.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Local Wispr.app"
INSTALLED_HELPER="$INSTALL_DIR/Local Wispr Paste Helper.app"
BUNDLE_ID="dev.local-wispr.LocalWispr"
HELPER_BUNDLE_ID="dev.local-wispr.PasteHelper"
RESET_ACCESSIBILITY=0

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

version_ge() {
    local lhs="$1"
    local rhs="$2"
    local lhs_part rhs_part
    local IFS=.
    read -ra lhs_parts <<<"$lhs"
    read -ra rhs_parts <<<"$rhs"

    for index in 0 1 2; do
        lhs_part="${lhs_parts[$index]:-0}"
        rhs_part="${rhs_parts[$index]:-0}"
        lhs_part="${lhs_part%%[^0-9]*}"
        rhs_part="${rhs_part%%[^0-9]*}"
        lhs_part="${lhs_part:-0}"
        rhs_part="${rhs_part:-0}"

        if ((10#$lhs_part > 10#$rhs_part)); then
            return 0
        fi

        if ((10#$lhs_part < 10#$rhs_part)); then
            return 1
        fi
    done

    return 0
}

reset_accessibility_tcc() {
    osascript -e 'quit app "System Settings"' >/dev/null 2>&1 || true

    for service in Accessibility PostEvent ListenEvent; do
        tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
        tccutil reset "$service" "$HELPER_BUNDLE_ID" >/dev/null 2>&1 || true
    done

    killall tccd >/dev/null 2>&1 || true
    echo "Reset Accessibility/PostEvent/ListenEvent records for Local Wispr and Paste Helper." >&2
}

install_bundle_contents "$BUILT_APP" "$INSTALLED_APP"

BUILT_HELPER_VERSION="$(bundle_version "$BUILT_HELPER")"
INSTALLED_HELPER_VERSION="$(bundle_version "$INSTALLED_HELPER")"

if [[ -d "$INSTALLED_HELPER" \
    && "${LOCAL_WISPR_UPDATE_HELPER:-0}" != "1" ]] \
    && version_ge "$INSTALLED_HELPER_VERSION" "$BUILT_HELPER_VERSION"; then
    echo "Keeping existing paste helper for stable Accessibility trust: $INSTALLED_HELPER" >&2
else
    if [[ -d "$INSTALLED_HELPER" && "${LOCAL_WISPR_UPDATE_HELPER:-0}" != "1" ]]; then
        echo "Updating paste helper from version $INSTALLED_HELPER_VERSION to $BUILT_HELPER_VERSION." >&2
        echo "Accessibility trust will be reset to avoid stale checked-but-untrusted TCC state." >&2
    fi

    install_bundle_contents "$BUILT_HELPER" "$INSTALLED_HELPER"

    if [[ "${LOCAL_WISPR_RESET_TCC_ON_HELPER_UPDATE:-1}" == "1" ]]; then
        RESET_ACCESSIBILITY=1
    fi
fi

if [[ "${LOCAL_WISPR_RESET_ACCESSIBILITY_ON_INSTALL:-0}" == "1" \
    || "${LOCAL_WISPR_RESET_TCC_ON_INSTALL:-0}" == "1" ]]; then
    RESET_ACCESSIBILITY=1
fi

codesign --verify --deep --strict "$INSTALLED_HELPER"
codesign --verify --deep --strict "$INSTALLED_APP"

if [[ "$RESET_ACCESSIBILITY" == "1" ]]; then
    reset_accessibility_tcc
fi

open_args=(-n)
while IFS='=' read -r name value; do
    if [[ "$name" == LOCAL_WISPR_* ]]; then
        open_args+=(--env "$name=$value")
    fi
done < <(env)

open "${open_args[@]}" "$INSTALLED_APP"

if [[ "$RESET_ACCESSIBILITY" == "1" && "${LOCAL_WISPR_OPEN_ACCESSIBILITY_ON_RESET:-1}" == "1" ]]; then
    open 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility'
fi

echo "$INSTALLED_APP"
echo "$INSTALLED_HELPER"

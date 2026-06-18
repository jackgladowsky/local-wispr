#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Local Wispr.app"
HELPER_APP_DIR="$ROOT_DIR/dist/Local Wispr Paste Helper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MOONSHINE_MODELS_DIR="$RESOURCES_DIR/MoonshineModels"
HELPER_CONTENTS_DIR="$HELPER_APP_DIR/Contents"
HELPER_MACOS_DIR="$HELPER_CONTENTS_DIR/MacOS"
HELPER_RESOURCES_DIR="$HELPER_CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

stamp_plist_version() {
    local plist="$1"

    if [[ -n "${LOCAL_WISPR_VERSION:-}" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${LOCAL_WISPR_VERSION}" "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${LOCAL_WISPR_VERSION}" "$plist"
    fi

    if [[ -n "${LOCAL_WISPR_BUILD_NUMBER:-}" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${LOCAL_WISPR_BUILD_NUMBER}" "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${LOCAL_WISPR_BUILD_NUMBER}" "$plist"
    fi
}

moonshine_default_model_source() {
    local language="$1"
    local arch="$2"
    local cache_root="${MOONSHINE_VOICE_CACHE:-$HOME/Library/Caches/moonshine_voice}"

    case "$arch" in
        tiny|base)
            printf '%s/download.moonshine.ai/model/%s-%s/quantized/%s-%s\n' "$cache_root" "$arch" "$language" "$arch" "$language"
            ;;
        *)
            printf '%s/download.moonshine.ai/model/%s-%s/quantized\n' "$cache_root" "$arch" "$language"
            ;;
    esac
}

moonshine_required_model_files() {
    local arch="$1"
    case "$arch" in
        tiny|base)
            printf '%s\n' encoder_model.ort decoder_model_merged.ort tokenizer.bin
            ;;
        *)
            printf '%s\n' adapter.ort cross_kv.ort decoder_kv.ort encoder.ort frontend.ort streaming_config.json tokenizer.bin
            ;;
    esac
}

copy_moonshine_native_model() {
    local language="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
    local arch="${LOCAL_WISPR_MOONSHINE_NATIVE_ARCH:-${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-medium-streaming}}"
    local source="${LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_SOURCE:-${LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR:-}}"
    local app_support_moonshine_dir="${LOCAL_WISPR_MOONSHINE_DIR:-$HOME/Library/Application Support/LocalWispr/Moonshine}"
    local app_support_source="$app_support_moonshine_dir/models/$language/$arch"

    if [[ -z "$source" ]]; then
        if [[ -d "$app_support_source" ]]; then
            source="$app_support_source"
        else
            source="$(moonshine_default_model_source "$language" "$arch")"
        fi
    fi

    if [[ ! -d "$source" ]]; then
        if [[ "${LOCAL_WISPR_REQUIRE_BUNDLED_MOONSHINE_MODEL:-0}" == "1" ]]; then
            echo "Missing Moonshine native model directory: $source" >&2
            echo "Run scripts/setup-moonshine-native.sh or set LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_SOURCE." >&2
            exit 1
        fi
        echo "Skipping bundled Moonshine model; not found: $source" >&2
        return 0
    fi

    local missing=0
    while IFS= read -r required_file; do
        if [[ ! -r "$source/$required_file" ]]; then
            echo "Moonshine model is missing required file: $source/$required_file" >&2
            missing=1
        fi
    done < <(moonshine_required_model_files "$arch")

    if [[ "$missing" != "0" ]]; then
        if [[ "${LOCAL_WISPR_REQUIRE_BUNDLED_MOONSHINE_MODEL:-0}" == "1" ]]; then
            exit 1
        fi
        echo "Skipping bundled Moonshine model because required files are missing." >&2
        return 0
    fi

    local destination="$MOONSHINE_MODELS_DIR/$language/$arch"
    mkdir -p "$(dirname "$destination")"
    rm -rf "$destination"
    ditto "$source" "$destination"
    echo "Bundled Moonshine native model: $destination" >&2
}

swift build -c release

rm -rf "$APP_DIR" "$HELPER_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
mkdir -p "$HELPER_MACOS_DIR" "$HELPER_RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/LocalWispr" "$MACOS_DIR/LocalWispr"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
copy_moonshine_native_model
if [[ "${LOCAL_WISPR_BUNDLE_MOONSHINE_SIDECAR:-0}" == "1" ]]; then
    cp "$ROOT_DIR/scripts/moonshine_server.py" "$RESOURCES_DIR/moonshine_server.py"
    chmod +x "$RESOURCES_DIR/moonshine_server.py"
fi
stamp_plist_version "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/LocalWispr"

cp "$ROOT_DIR/.build/release/LocalWisprPasteHelper" "$HELPER_MACOS_DIR/LocalWisprPasteHelper"
cp "$ROOT_DIR/Packaging/PasteHelperInfo.plist" "$HELPER_CONTENTS_DIR/Info.plist"
stamp_plist_version "$HELPER_CONTENTS_DIR/Info.plist"
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

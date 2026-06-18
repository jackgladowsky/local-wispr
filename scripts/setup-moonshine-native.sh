#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MOONSHINE_DIR="${LOCAL_WISPR_MOONSHINE_DIR:-$APP_SUPPORT/Moonshine}"
MOONSHINE_LANGUAGE="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
MOONSHINE_ARCH="${LOCAL_WISPR_MOONSHINE_NATIVE_ARCH:-${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-small-streaming}}"
MOONSHINE_MODEL_DIR="${LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR:-$MOONSHINE_DIR/models/$MOONSHINE_LANGUAGE/$MOONSHINE_ARCH}"

model_base_url() {
    local language="$1"
    local arch="$2"

    case "$arch" in
        tiny|base)
            printf 'https://download.moonshine.ai/model/%s-%s/quantized/%s-%s\n' "$arch" "$language" "$arch" "$language"
            ;;
        *)
            printf 'https://download.moonshine.ai/model/%s-%s/quantized\n' "$arch" "$language"
            ;;
    esac
}

required_components() {
    local language="$1"
    local arch="$2"

    case "$arch" in
        tiny|base)
            printf '%s\n' encoder_model.ort decoder_model_merged.ort tokenizer.bin
            if [[ "$language" == "en" ]]; then
                printf '%s\n' decoder_with_attention.ort
            fi
            ;;
        *)
            printf '%s\n' adapter.ort cross_kv.ort decoder_kv.ort encoder.ort frontend.ort streaming_config.json tokenizer.bin
            if [[ "$language" == "en" ]]; then
                printf '%s\n' decoder_kv_with_attention.ort
            fi
            ;;
    esac
}

download_component() {
    local base_url="$1"
    local component="$2"
    local destination="$MOONSHINE_MODEL_DIR/$component"
    local partial="$destination.partial"

    mkdir -p "$(dirname "$destination")"
    if [[ -s "$destination" ]]; then
        echo "Moonshine component already exists: $destination"
        return 0
    fi

    echo "Downloading Moonshine component: $component"
    curl -L --fail --continue-at - --progress-bar "$base_url/$component" -o "$partial"
    mv "$partial" "$destination"
}

case "$MOONSHINE_ARCH" in
    tiny|base|tiny-streaming|base-streaming|small-streaming|medium-streaming) ;;
    *)
        echo "Unsupported Moonshine architecture: $MOONSHINE_ARCH" >&2
        exit 1
        ;;
esac

if [[ "$MOONSHINE_LANGUAGE" != "en" ]]; then
    echo "Warning: non-English Moonshine models may use a non-commercial license. Review Moonshine licensing before release." >&2
fi

BASE_URL="$(model_base_url "$MOONSHINE_LANGUAGE" "$MOONSHINE_ARCH")"
mkdir -p "$MOONSHINE_MODEL_DIR"

while IFS= read -r component; do
    download_component "$BASE_URL" "$component"
done < <(required_components "$MOONSHINE_LANGUAGE" "$MOONSHINE_ARCH")

echo
echo "Moonshine native model ready: $MOONSHINE_MODEL_DIR"
echo "Local Wispr will discover this default model path automatically."

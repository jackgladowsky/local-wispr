#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MOONSHINE_DIR="${LOCAL_WISPR_MOONSHINE_DIR:-$APP_SUPPORT/Moonshine}"
MOONSHINE_VENV="${LOCAL_WISPR_MOONSHINE_VENV:-$MOONSHINE_DIR/venv}"
MOONSHINE_BACKEND="${LOCAL_WISPR_MOONSHINE_BACKEND:-voice}"
MOONSHINE_MODEL="${LOCAL_WISPR_MOONSHINE_MODEL:-UsefulSensors/moonshine-streaming-small}"
MOONSHINE_LANGUAGE="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
MOONSHINE_VOICE_ARCH="${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-medium-streaming}"
MOONSHINE_NATIVE_ARCH="${LOCAL_WISPR_MOONSHINE_NATIVE_ARCH:-$MOONSHINE_VOICE_ARCH}"
MOONSHINE_NATIVE_MODEL_CONFIGURED="${LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR:-${LOCAL_WISPR_MOONSHINE_MODEL_DIR:-}}"
MOONSHINE_NATIVE_MODEL_DIR="${MOONSHINE_NATIVE_MODEL_CONFIGURED:-$MOONSHINE_DIR/models/$MOONSHINE_LANGUAGE/$MOONSHINE_NATIVE_ARCH}"
MOONSHINE_SERVER_URL="${LOCAL_WISPR_MOONSHINE_SERVER_URL:-${LOCAL_WISPR_MOONSHINE_SERVER_ENDPOINT:-http://127.0.0.1:8179/transcribe}}"
CLEANUP_MODEL="${LOCAL_WISPR_CLEANUP_MODEL:-$APP_SUPPORT/Models/cleanup/cleanup.gguf}"
LLAMA_SERVER_URL="${LOCAL_WISPR_LLAMA_SERVER_URL:-${LOCAL_WISPR_LLAMA_SERVER_ENDPOINT:-http://127.0.0.1:8080/completion}}"

is_loopback_url() {
    local url="$1"
    python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
host = (parsed.hostname or "").lower()
scheme = (parsed.scheme or "").lower()
sys.exit(0 if scheme in {"http", "https"} and host in {"127.0.0.1", "localhost", "::1"} else 1)
PY
}

url_origin() {
    local url="$1"
    python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse, urlunparse

parsed = urlparse(sys.argv[1])
scheme = parsed.scheme or "http"
netloc = parsed.netloc
print(urlunparse((scheme, netloc, "/", "", "", "")))
PY
}

status_line() {
    printf '%-20s %s\n' "$1" "$2"
}

find_executable() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/opt/llama.cpp/bin/$name" \
        "/usr/local/opt/llama.cpp/bin/$name" \
        "/opt/homebrew/bin/$name" \
        "/usr/local/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

moonshine_default_model_source() {
    local cache_root="${MOONSHINE_VOICE_CACHE:-$HOME/Library/Caches/moonshine_voice}"
    case "$MOONSHINE_NATIVE_ARCH" in
        tiny|base)
            printf '%s/download.moonshine.ai/model/%s-%s/quantized/%s-%s\n' "$cache_root" "$MOONSHINE_NATIVE_ARCH" "$MOONSHINE_LANGUAGE" "$MOONSHINE_NATIVE_ARCH" "$MOONSHINE_LANGUAGE"
            ;;
        *)
            printf '%s/download.moonshine.ai/model/%s-%s/quantized\n' "$cache_root" "$MOONSHINE_NATIVE_ARCH" "$MOONSHINE_LANGUAGE"
            ;;
    esac
}

moonshine_native_model_ready() {
    local directory="$1"
    local files
    case "$MOONSHINE_NATIVE_ARCH" in
        tiny|base) files=(encoder_model.ort decoder_model_merged.ort tokenizer.bin) ;;
        *) files=(adapter.ort cross_kv.ort decoder_kv.ort encoder.ort frontend.ort streaming_config.json tokenizer.bin) ;;
    esac

    [[ -d "$directory" ]] || return 1
    local file
    for file in "${files[@]}"; do
        [[ -r "$directory/$file" ]] || return 1
    done
}

echo "Local Wispr engine check"
echo

MOONSHINE_NATIVE_CACHE_DIR="$(moonshine_default_model_source)"
if moonshine_native_model_ready "$MOONSHINE_NATIVE_MODEL_DIR"; then
    status_line "Moonshine native:" "$MOONSHINE_LANGUAGE/$MOONSHINE_NATIVE_ARCH at $MOONSHINE_NATIVE_MODEL_DIR"
elif [[ -n "$MOONSHINE_NATIVE_MODEL_CONFIGURED" ]]; then
    status_line "Moonshine native:" "configured path is not ready: $MOONSHINE_NATIVE_MODEL_DIR"
elif moonshine_native_model_ready "$MOONSHINE_NATIVE_CACHE_DIR"; then
    status_line "Moonshine native:" "$MOONSHINE_LANGUAGE/$MOONSHINE_NATIVE_ARCH at $MOONSHINE_NATIVE_CACHE_DIR"
else
    status_line "Moonshine native:" "missing; run scripts/setup-moonshine-native.sh"
fi

if [[ -x "$MOONSHINE_VENV/bin/python" ]]; then
    status_line "Moonshine Python:" "$MOONSHINE_VENV/bin/python"
else
    status_line "Moonshine Python:" "missing; run scripts/setup-local-engines.sh"
fi

if [[ -r "$MOONSHINE_DIR/moonshine_server.py" ]]; then
    status_line "Moonshine sidecar:" "$MOONSHINE_DIR/moonshine_server.py"
elif [[ -r "$SCRIPT_DIR/moonshine_server.py" ]]; then
    status_line "Moonshine sidecar:" "$SCRIPT_DIR/moonshine_server.py"
else
    status_line "Moonshine sidecar:" "missing"
fi

status_line "Moonshine backend:" "$MOONSHINE_BACKEND"
status_line "Moonshine model:" "$MOONSHINE_MODEL"
status_line "Moonshine voice:" "$MOONSHINE_LANGUAGE/$MOONSHINE_VOICE_ARCH"

if ! is_loopback_url "$MOONSHINE_SERVER_URL"; then
    status_line "Moonshine server:" "refusing non-loopback URL $MOONSHINE_SERVER_URL"
elif curl -fsS --max-time 2 "$(url_origin "$MOONSHINE_SERVER_URL")" >/dev/null 2>&1; then
    status_line "Moonshine server:" "responding at $MOONSHINE_SERVER_URL"
else
    status_line "Moonshine server:" "not running at $MOONSHINE_SERVER_URL"
fi

if llama_cli="$(find_executable llama-cli)"; then
    status_line "llama-cli:" "$llama_cli"
else
    status_line "llama-cli:" "missing"
fi

if llama_server="$(find_executable llama-server)"; then
    status_line "llama-server:" "$llama_server"
else
    status_line "llama-server:" "missing"
fi

if [[ -f "$CLEANUP_MODEL" ]]; then
    status_line "Cleanup model:" "$CLEANUP_MODEL"
else
    status_line "Cleanup model:" "missing $CLEANUP_MODEL"
fi

if ! is_loopback_url "$LLAMA_SERVER_URL" && [[ "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" != "1" ]]; then
    status_line "llama server:" "skipped non-loopback URL $LLAMA_SERVER_URL"
elif curl -fsS --max-time 2 "$LLAMA_SERVER_URL" \
    -H 'Content-Type: application/json' \
    -d '{"prompt":"hello","n_predict":1,"stream":false}' \
    >/dev/null 2>&1; then
    status_line "llama server:" "responding at $LLAMA_SERVER_URL"
else
    status_line "llama server:" "not running at $LLAMA_SERVER_URL"
fi

echo
echo "Local Wispr uses native Moonshine STT by default and keeps the loopback sidecar as an optional fallback."
echo "The app can run with Basic Local Cleanup when llama.cpp cleanup is unavailable."

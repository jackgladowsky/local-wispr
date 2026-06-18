#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MOONSHINE_DIR="${LOCAL_WISPR_MOONSHINE_DIR:-$APP_SUPPORT/Moonshine}"
MOONSHINE_VENV="${LOCAL_WISPR_MOONSHINE_VENV:-$MOONSHINE_DIR/venv}"
MOONSHINE_BACKEND="${LOCAL_WISPR_MOONSHINE_BACKEND:-voice}"
MOONSHINE_MODEL="${LOCAL_WISPR_MOONSHINE_MODEL:-UsefulSensors/moonshine-streaming-small}"
MOONSHINE_LANGUAGE="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
MOONSHINE_VOICE_ARCH="${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-small-streaming}"
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

echo "Local Wispr engine smoke test"
echo

MOONSHINE_NATIVE_CACHE_DIR="$(moonshine_default_model_source)"
if moonshine_native_model_ready "$MOONSHINE_NATIVE_MODEL_DIR"; then
    echo "Moonshine native: ready ($MOONSHINE_NATIVE_MODEL_DIR)"
elif [[ -n "$MOONSHINE_NATIVE_MODEL_CONFIGURED" ]]; then
    echo "Moonshine native: configured path is not ready ($MOONSHINE_NATIVE_MODEL_DIR)"
elif moonshine_native_model_ready "$MOONSHINE_NATIVE_CACHE_DIR"; then
    echo "Moonshine native: ready ($MOONSHINE_NATIVE_CACHE_DIR)"
else
    echo "Moonshine native: missing; run scripts/setup-moonshine-native.sh"
fi

if [[ -x "$MOONSHINE_VENV/bin/python" ]]; then
    echo "Moonshine Python: ready ($MOONSHINE_VENV/bin/python)"
else
    echo "Moonshine Python: missing; run scripts/setup-local-engines.sh"
fi

if [[ -r "$MOONSHINE_DIR/moonshine_server.py" ]]; then
    echo "Moonshine sidecar: ready ($MOONSHINE_DIR/moonshine_server.py)"
elif [[ -r "$SCRIPT_DIR/moonshine_server.py" ]]; then
    echo "Moonshine sidecar: ready ($SCRIPT_DIR/moonshine_server.py)"
else
    echo "Moonshine sidecar: missing"
fi

echo "Moonshine backend: $MOONSHINE_BACKEND"
echo "Moonshine model: $MOONSHINE_MODEL"
echo "Moonshine voice: $MOONSHINE_LANGUAGE/$MOONSHINE_VOICE_ARCH"

if is_loopback_url "$MOONSHINE_SERVER_URL"; then
    if curl -fsS --max-time 2 "$(url_origin "$MOONSHINE_SERVER_URL")" >/dev/null 2>&1; then
        echo "Moonshine server: reachable at $MOONSHINE_SERVER_URL"
    else
        echo "Moonshine server: not running at $MOONSHINE_SERVER_URL"
    fi
else
    echo "Moonshine server: refused non-loopback URL $MOONSHINE_SERVER_URL"
fi

if [[ -f "$CLEANUP_MODEL" ]]; then
    echo "llama.cpp cleanup model: ready ($CLEANUP_MODEL)"
else
    echo "llama.cpp cleanup model: missing ($CLEANUP_MODEL)"
fi

if is_loopback_url "$LLAMA_SERVER_URL" || [[ "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" == "1" ]]; then
    server_response="$(
        curl -fsS --max-time 3 "$LLAMA_SERVER_URL" \
            -H 'Content-Type: application/json' \
            -d '{"prompt":"Return only this word: ready","n_predict":8,"temperature":0.1,"cache_prompt":true,"stream":false}' \
            2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("content", "").strip())' \
        2>/dev/null || true
    )"
else
    server_response=""
    echo "llama.cpp cleanup server: skipped non-loopback URL $LLAMA_SERVER_URL"
fi

if [[ -n "$server_response" ]]; then
    echo "llama.cpp cleanup server: ready ($server_response)"
elif is_loopback_url "$LLAMA_SERVER_URL" || [[ "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" == "1" ]]; then
    echo "llama.cpp cleanup server: not running at $LLAMA_SERVER_URL"
fi

echo
if [[ -z "${server_response:-}" ]]; then
    echo "Tip: Local Wispr will use Basic Local Cleanup unless you start llama-server and set LOCAL_WISPR_REWRITE_ENGINE=llama-server."
fi
echo "Tip: Local Wispr uses native Moonshine by default; set LOCAL_WISPR_SETUP_MOONSHINE_SERVER=1 during setup for the Python sidecar fallback."

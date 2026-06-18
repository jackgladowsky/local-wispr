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

echo "Local Wispr engine smoke test"
echo

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
echo "Tip: Local Wispr starts/uses loopback Moonshine by default after scripts/setup-local-engines.sh."

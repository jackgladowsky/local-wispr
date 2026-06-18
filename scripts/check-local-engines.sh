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

echo "Local Wispr engine check"
echo

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
echo "Local Wispr uses the loopback Moonshine sidecar for STT."
echo "The app can run with Basic Local Cleanup when llama.cpp cleanup is unavailable."

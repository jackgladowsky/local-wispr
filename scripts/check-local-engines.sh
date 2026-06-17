#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_MODEL="${LOCAL_WISPR_WHISPER_MODEL:-$APP_SUPPORT/Models/whisper/ggml-base.en.bin}"
WHISPER_SERVER_URL="${LOCAL_WISPR_WHISPER_SERVER_URL:-${LOCAL_WISPR_WHISPER_SERVER_ENDPOINT:-http://127.0.0.1:8178/inference}}"
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
    printf '%-18s %s\n' "$1" "$2"
}

find_executable() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/opt/whisper-cpp/bin/$name" \
        "/usr/local/opt/whisper-cpp/bin/$name" \
        "/opt/homebrew/opt/llama.cpp/bin/$name" \
        "/usr/local/opt/llama.cpp/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

echo "Local Wispr engine check"
echo

if whisper_cli="$(find_executable whisper-cli)"; then
    status_line "STT executable:" "$whisper_cli"
else
    status_line "STT executable:" "missing whisper-cli"
fi

if [[ -f "$WHISPER_MODEL" ]]; then
    status_line "Whisper model:" "$WHISPER_MODEL"
else
    status_line "Whisper model:" "missing $WHISPER_MODEL"
fi

if whisper_server="$(find_executable whisper-server)"; then
    status_line "whisper-server:" "$whisper_server"
else
    status_line "whisper-server:" "missing"
fi

if ! is_loopback_url "$WHISPER_SERVER_URL"; then
    status_line "whisper server:" "refusing non-loopback URL $WHISPER_SERVER_URL"
elif curl -fsS --max-time 2 "$(url_origin "$WHISPER_SERVER_URL")" >/dev/null 2>&1; then
    status_line "whisper server:" "responding at $WHISPER_SERVER_URL"
else
    status_line "whisper server:" "not running at $WHISPER_SERVER_URL"
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
echo "The app can run with Basic Local Cleanup when llama.cpp cleanup is unavailable."
echo "When available, Local Wispr starts/uses loopback whisper-server by default with whisper-cli fallback."

#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_MODEL="$APP_SUPPORT/Models/whisper/ggml-base.en.bin"
CLEANUP_MODEL="${LOCAL_WISPR_CLEANUP_MODEL:-$APP_SUPPORT/Models/cleanup/cleanup.gguf}"
LLAMA_SERVER_URL="${LOCAL_WISPR_LLAMA_SERVER_URL:-${LOCAL_WISPR_LLAMA_SERVER_ENDPOINT:-http://127.0.0.1:8080/completion}}"

is_loopback_endpoint() {
    [[ "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" == "1" ]] && return 0

    python3 - "$LLAMA_SERVER_URL" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
host = (parsed.hostname or "").lower()
sys.exit(0 if host in {"127.0.0.1", "localhost", "::1"} else 1)
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

if command -v whisper-cli >/dev/null 2>&1; then
    status_line "STT executable:" "$(command -v whisper-cli)"
else
    status_line "STT executable:" "missing whisper-cli"
fi

if [[ -f "$WHISPER_MODEL" ]]; then
    status_line "Whisper model:" "$WHISPER_MODEL"
else
    status_line "Whisper model:" "missing $WHISPER_MODEL"
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

if ! is_loopback_endpoint; then
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

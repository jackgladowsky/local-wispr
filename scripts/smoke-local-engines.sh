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

find_executable() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/opt/whisper-cpp/bin/$name" \
        "/usr/local/opt/whisper-cpp/bin/$name" \
        "/opt/homebrew/bin/$name" \
        "/usr/local/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

echo "Local Wispr engine smoke test"
echo

if find_executable whisper-cli >/dev/null && [[ -f "$WHISPER_MODEL" ]]; then
    echo "whisper.cpp CLI: ready"
else
    echo "whisper.cpp CLI: missing executable or model"
fi

if find_executable whisper-server >/dev/null && [[ -f "$WHISPER_MODEL" ]]; then
    echo "whisper.cpp server binary: ready"
else
    echo "whisper.cpp server binary: missing executable or model"
fi

if is_loopback_url "$WHISPER_SERVER_URL"; then
    if curl -fsS --max-time 2 "$(url_origin "$WHISPER_SERVER_URL")" >/dev/null 2>&1; then
        echo "whisper.cpp server: reachable at $WHISPER_SERVER_URL"
    else
        echo "whisper.cpp server: not running at $WHISPER_SERVER_URL"
    fi
else
    echo "whisper.cpp server: refused non-loopback URL $WHISPER_SERVER_URL"
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
echo "Tip: when available, Local Wispr starts/uses loopback whisper-server by default with whisper-cli fallback."

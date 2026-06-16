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

echo "Local Wispr engine smoke test"
echo

if [[ -x /opt/homebrew/bin/whisper-cli || -n "$(command -v whisper-cli 2>/dev/null)" ]] && [[ -f "$WHISPER_MODEL" ]]; then
    echo "whisper.cpp: ready"
else
    echo "whisper.cpp: missing executable or model"
fi

if [[ -f "$CLEANUP_MODEL" ]]; then
    echo "llama.cpp cleanup model: ready ($CLEANUP_MODEL)"
else
    echo "llama.cpp cleanup model: missing ($CLEANUP_MODEL)"
fi

if is_loopback_endpoint; then
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
elif is_loopback_endpoint; then
    echo "llama.cpp cleanup server: not running at $LLAMA_SERVER_URL"
fi

echo
if [[ -z "$server_response" ]]; then
    echo "Tip: Local Wispr will use Basic Local Cleanup unless you start llama-server and set LOCAL_WISPR_REWRITE_ENGINE=llama-server."
fi

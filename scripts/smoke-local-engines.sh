#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_MODEL="$APP_SUPPORT/Models/whisper/ggml-base.en.bin"

echo "Local Wispr engine smoke test"
echo

if [[ -x /opt/homebrew/bin/whisper-cli && -f "$WHISPER_MODEL" ]]; then
    echo "whisper.cpp: ready"
else
    echo "whisper.cpp: missing executable or model"
fi

if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    response="$(
        curl -fsS http://127.0.0.1:11434/api/generate \
            -H 'Content-Type: application/json' \
            -d '{
                "model": "qwen3:0.6b",
                "prompt": "Rewrite this transcript into clean text. Return only the cleaned text. Transcript: hello world",
                "stream": false,
                "think": false,
                "options": {
                    "temperature": 0.1,
                    "num_predict": 64
                }
            }' \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("response", "").strip())'
    )"

    if [[ "$response" == "hello world" || "$response" == "Hello world." || "$response" == "Hello world" ]]; then
        echo "Ollama cleanup: ready ($response)"
    else
        echo "Ollama cleanup: unexpected response ($response)"
        exit 1
    fi
else
    echo "Ollama cleanup: server not running"
fi

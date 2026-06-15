#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_MODEL="$APP_SUPPORT/Models/whisper/ggml-base.en.bin"

echo "Local Wispr engine check"
echo

if command -v whisper-cli >/dev/null 2>&1; then
    echo "STT executable: $(command -v whisper-cli)"
else
    echo "STT executable: missing whisper-cli"
fi

if [[ -f "$WHISPER_MODEL" ]]; then
    echo "Whisper model:   $WHISPER_MODEL"
else
    echo "Whisper model:   missing $WHISPER_MODEL"
fi

if command -v ollama >/dev/null 2>&1; then
    echo "Ollama:          $(command -v ollama)"
    if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo "Ollama server:   running"
        if ollama list | grep -q '^qwen3:0.6b'; then
            echo "Cleanup model:   qwen3:0.6b"
        else
            echo "Cleanup model:   qwen3:0.6b not pulled"
        fi
    else
        echo "Ollama server:   not running"
    fi
else
    echo "Ollama:          missing"
fi

echo
echo "The app can run with Basic Local Cleanup even when Ollama is unavailable."

#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_DIR="$APP_SUPPORT/Models/whisper"
WHISPER_MODEL="$WHISPER_DIR/ggml-base.en.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

WITH_OLLAMA="${LOCAL_WISPR_WITH_OLLAMA:-1}"
OLLAMA_MODEL="${LOCAL_WISPR_OLLAMA_MODEL:-qwen3:0.6b}"

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required for this setup script." >&2
    exit 1
fi

brew_safe() {
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew "$@"
}

echo "Installing whisper-cpp..."
brew_safe list whisper-cpp >/dev/null 2>&1 || brew_safe install whisper-cpp

mkdir -p "$WHISPER_DIR"
if [[ ! -f "$WHISPER_MODEL" ]]; then
    echo "Downloading Whisper base.en model..."
    curl -L --fail --progress-bar "$WHISPER_MODEL_URL" -o "$WHISPER_MODEL"
else
    echo "Whisper model already exists: $WHISPER_MODEL"
fi

if [[ "$WITH_OLLAMA" == "1" ]]; then
    echo "Installing Ollama..."
    brew_safe list ollama >/dev/null 2>&1 || brew_safe install ollama

    if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo "Starting Ollama service..."
        brew_safe services start ollama
        sleep 3
    fi

    echo "Pulling cleanup model: $OLLAMA_MODEL"
    ollama pull "$OLLAMA_MODEL"
else
    echo "Skipping Ollama setup because LOCAL_WISPR_WITH_OLLAMA=$WITH_OLLAMA"
fi

"$(dirname "$0")/check-local-engines.sh"

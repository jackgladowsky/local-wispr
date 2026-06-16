#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
WHISPER_DIR="$APP_SUPPORT/Models/whisper"
CLEANUP_DIR="$APP_SUPPORT/Models/cleanup"
WHISPER_MODEL="$WHISPER_DIR/ggml-base.en.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
CLEANUP_MODEL="$CLEANUP_DIR/cleanup.gguf"
CLEANUP_MODEL_URL="${LOCAL_WISPR_CLEANUP_MODEL_URL:-https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
WITH_LLAMA_CPP="${LOCAL_WISPR_WITH_LLAMA_CPP:-1}"

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

if [[ "$WITH_LLAMA_CPP" == "1" ]]; then
    echo "Installing llama.cpp..."
    if ! brew_safe list llama.cpp >/dev/null 2>&1; then
        brew_safe install llama.cpp || brew_safe list llama.cpp >/dev/null 2>&1
    fi

    mkdir -p "$CLEANUP_DIR"
    if [[ ! -f "$CLEANUP_MODEL" ]]; then
        echo "Downloading cleanup GGUF model..."
        curl -L --fail --progress-bar "$CLEANUP_MODEL_URL" -o "$CLEANUP_MODEL"
    else
        echo "Cleanup model already exists: $CLEANUP_MODEL"
    fi
else
    echo "Skipping llama.cpp setup because LOCAL_WISPR_WITH_LLAMA_CPP=$WITH_LLAMA_CPP"
fi

"$(dirname "$0")/check-local-engines.sh"

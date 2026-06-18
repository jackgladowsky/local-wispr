#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
CLEANUP_DIR="$APP_SUPPORT/Models/cleanup"
CLEANUP_MODEL="$CLEANUP_DIR/cleanup.gguf"
CLEANUP_MODEL_URL="${LOCAL_WISPR_CLEANUP_MODEL_URL:-https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf}"
WITH_LLAMA_CPP="${LOCAL_WISPR_WITH_LLAMA_CPP:-1}"
SETUP_MOONSHINE_SERVER="${LOCAL_WISPR_SETUP_MOONSHINE_SERVER:-0}"

"$SCRIPT_DIR/setup-moonshine-native.sh"

if [[ "$SETUP_MOONSHINE_SERVER" == "1" ]]; then
    "$SCRIPT_DIR/setup-moonshine-server.sh"
else
    echo "Skipping Python Moonshine sidecar setup because LOCAL_WISPR_SETUP_MOONSHINE_SERVER=$SETUP_MOONSHINE_SERVER"
fi

if [[ "$WITH_LLAMA_CPP" == "1" ]]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required for optional llama.cpp cleanup setup." >&2
        echo "Set LOCAL_WISPR_WITH_LLAMA_CPP=0 to skip cleanup model setup." >&2
        exit 1
    fi

    brew_safe() {
        HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_REQUIRE_TAP_TRUST=1 brew "$@"
    }

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

"$SCRIPT_DIR/check-local-engines.sh"

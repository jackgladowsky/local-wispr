#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MOONSHINE_DIR="${LOCAL_WISPR_MOONSHINE_DIR:-$APP_SUPPORT/Moonshine}"
MOONSHINE_VENV="${LOCAL_WISPR_MOONSHINE_VENV:-$MOONSHINE_DIR/venv}"
MOONSHINE_BACKEND="${LOCAL_WISPR_MOONSHINE_BACKEND:-voice}"
MOONSHINE_MODEL="${LOCAL_WISPR_MOONSHINE_MODEL:-UsefulSensors/moonshine-streaming-small}"
MOONSHINE_LANGUAGE="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
MOONSHINE_VOICE_ARCH="${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-medium-streaming}"
PYTHON_BIN="${LOCAL_WISPR_MOONSHINE_PYTHON:-python3}"
PRELOAD_MODEL="${LOCAL_WISPR_MOONSHINE_PRELOAD_MODEL:-1}"
INSTALL_TRANSFORMERS="${LOCAL_WISPR_MOONSHINE_INSTALL_TRANSFORMERS:-0}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "Python 3 is required to set up the Moonshine server." >&2
    exit 1
fi

mkdir -p "$MOONSHINE_DIR"
cp "$SCRIPT_DIR/moonshine_server.py" "$MOONSHINE_DIR/moonshine_server.py"
chmod +x "$MOONSHINE_DIR/moonshine_server.py"

if [[ ! -x "$MOONSHINE_VENV/bin/python" ]]; then
    echo "Creating Moonshine virtualenv: $MOONSHINE_VENV"
    "$PYTHON_BIN" -m venv "$MOONSHINE_VENV"
fi

PYTHON="$MOONSHINE_VENV/bin/python"
PIP="$MOONSHINE_VENV/bin/pip"

echo "Installing Moonshine Voice Python dependencies..."
"$PYTHON" -m pip install --upgrade pip wheel setuptools
"$PIP" install --upgrade 'moonshine-voice>=0.0.62'

if [[ "$MOONSHINE_BACKEND" == "transformers" || "$INSTALL_TRANSFORMERS" == "1" ]]; then
    echo "Installing optional Transformers backend dependencies..."
    "$PIP" install --upgrade \
        'torch>=2.2' \
        'transformers>=4.57.0' \
        'accelerate>=0.28' \
        'soundfile>=0.12'
fi

if [[ "$PRELOAD_MODEL" == "1" && "$MOONSHINE_BACKEND" == "voice" ]]; then
    echo "Preloading Moonshine Voice model: language=$MOONSHINE_LANGUAGE arch=$MOONSHINE_VOICE_ARCH"
    LOCAL_WISPR_MOONSHINE_LANGUAGE="$MOONSHINE_LANGUAGE" \
    LOCAL_WISPR_MOONSHINE_VOICE_ARCH="$MOONSHINE_VOICE_ARCH" \
    "$PYTHON" - <<'PY'
import os
from moonshine_voice import Transcriber, get_model_for_language, string_to_model_arch

language = os.environ["LOCAL_WISPR_MOONSHINE_LANGUAGE"]
arch_name = os.environ["LOCAL_WISPR_MOONSHINE_VOICE_ARCH"]
model_path, model_arch = get_model_for_language(language, string_to_model_arch(arch_name))
transcriber = Transcriber(model_path, model_arch)
transcriber.close()
print(f"Moonshine Voice model is cached: {language}/{arch_name} at {model_path}")
PY
elif [[ "$PRELOAD_MODEL" == "1" ]]; then
    echo "Preloading Transformers Moonshine model into Hugging Face cache: $MOONSHINE_MODEL"
    LOCAL_WISPR_MOONSHINE_MODEL="$MOONSHINE_MODEL" "$PYTHON" - <<'PY'
import os
from transformers import pipeline

model = os.environ["LOCAL_WISPR_MOONSHINE_MODEL"]
print(f"Downloading/loading {model}...")
pipeline(task="automatic-speech-recognition", model=model, device="cpu")
print("Transformers Moonshine model is cached.")
PY
else
    echo "Skipping model preload because LOCAL_WISPR_MOONSHINE_PRELOAD_MODEL=$PRELOAD_MODEL"
fi

echo
echo "Moonshine sidecar setup complete. Local Wispr uses native Moonshine by default and starts this loopback sidecar only as a fallback when configured."
echo
echo "You can also run the sidecar manually with:"
echo "  scripts/start-moonshine-server.sh"

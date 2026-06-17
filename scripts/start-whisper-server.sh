#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MODEL="${LOCAL_WISPR_WHISPER_MODEL:-$APP_SUPPORT/Models/whisper/ggml-base.en.bin}"
HOST="${LOCAL_WISPR_WHISPER_SERVER_HOST:-127.0.0.1}"
PORT="${LOCAL_WISPR_WHISPER_SERVER_PORT:-8178}"
INFERENCE_PATH="${LOCAL_WISPR_WHISPER_SERVER_INFERENCE_PATH:-/inference}"

if [[ "$HOST" != "127.0.0.1" && "$HOST" != "localhost" && "$HOST" != "::1" ]]; then
    echo "Refusing to bind whisper-server to non-loopback host: $HOST" >&2
    echo "Local Wispr STT audio must stay on this Mac; use 127.0.0.1, localhost, or ::1." >&2
    exit 64
fi

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

WHISPER_SERVER="$(find_executable whisper-server)" || {
    echo "whisper-server not found. Run scripts/setup-local-engines.sh first." >&2
    exit 69
}

if [[ ! -f "$MODEL" ]]; then
    echo "Whisper model not found: $MODEL" >&2
    echo "Run scripts/setup-local-engines.sh first or set LOCAL_WISPR_WHISPER_MODEL." >&2
    exit 69
fi

echo "Starting whisper.cpp server"
echo "Model: $MODEL"
echo "URL:   http://$HOST:$PORT$INFERENCE_PATH"
echo
echo "Local Wispr also starts a managed loopback server by default when this binary and model are available."
echo "For a custom already-running URL, launch the app with:"
echo "LOCAL_WISPR_WHISPER_SERVER_URL=http://$HOST:$PORT$INFERENCE_PATH scripts/install-app.sh"
echo

args=(
    -m "$MODEL"
    --host "$HOST"
    --port "$PORT"
    --inference-path "$INFERENCE_PATH"
    -nt
)

if [[ "${LOCAL_WISPR_WHISPER_SUPPRESS_NST:-1}" == "1" ]]; then
    args+=(-sns)
fi

if [[ -n "${LOCAL_WISPR_WHISPER_THREADS:-}" ]]; then
    args+=(--threads "$LOCAL_WISPR_WHISPER_THREADS")
fi

if [[ -n "${LOCAL_WISPR_WHISPER_PROCESSORS:-}" ]]; then
    args+=(--processors "$LOCAL_WISPR_WHISPER_PROCESSORS")
fi

if [[ -n "${LOCAL_WISPR_WHISPER_BEAM_SIZE:-}" ]]; then
    args+=(--beam-size "$LOCAL_WISPR_WHISPER_BEAM_SIZE")
fi

if [[ -n "${LOCAL_WISPR_WHISPER_BEST_OF:-}" ]]; then
    args+=(--best-of "$LOCAL_WISPR_WHISPER_BEST_OF")
fi

if [[ -n "${LOCAL_WISPR_WHISPER_AUDIO_CTX:-}" ]]; then
    args+=(--audio-ctx "$LOCAL_WISPR_WHISPER_AUDIO_CTX")
fi

if [[ "${LOCAL_WISPR_WHISPER_NO_FALLBACK:-0}" == "1" ]]; then
    args+=(--no-fallback)
fi

if [[ "${LOCAL_WISPR_WHISPER_NO_GPU:-0}" == "1" ]]; then
    args+=(--no-gpu)
fi

if [[ "${LOCAL_WISPR_WHISPER_NO_FLASH_ATTN:-0}" == "1" ]]; then
    args+=(--no-flash-attn)
fi

if [[ -n "${LOCAL_WISPR_WHISPER_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=($LOCAL_WISPR_WHISPER_EXTRA_ARGS)
    args+=("${extra_args[@]}")
fi

exec "$WHISPER_SERVER" "${args[@]}"

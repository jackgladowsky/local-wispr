#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MOONSHINE_DIR="${LOCAL_WISPR_MOONSHINE_DIR:-$APP_SUPPORT/Moonshine}"
MOONSHINE_VENV="${LOCAL_WISPR_MOONSHINE_VENV:-$MOONSHINE_DIR/venv}"
MOONSHINE_HOST="${LOCAL_WISPR_MOONSHINE_HOST:-127.0.0.1}"
MOONSHINE_PORT="${LOCAL_WISPR_MOONSHINE_PORT:-8179}"
MOONSHINE_BACKEND="${LOCAL_WISPR_MOONSHINE_BACKEND:-voice}"
MOONSHINE_MODEL="${LOCAL_WISPR_MOONSHINE_MODEL:-UsefulSensors/moonshine-streaming-small}"
MOONSHINE_LANGUAGE="${LOCAL_WISPR_MOONSHINE_LANGUAGE:-en}"
MOONSHINE_VOICE_ARCH="${LOCAL_WISPR_MOONSHINE_VOICE_ARCH:-small-streaming}"

is_loopback_host() {
    local host
    host="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$host" in
        127.0.0.1|localhost|::1) return 0 ;;
        *) return 1 ;;
    esac
}

if ! is_loopback_host "$MOONSHINE_HOST"; then
    echo "Refusing to bind Moonshine server to non-loopback host: $MOONSHINE_HOST" >&2
    echo "Local Wispr STT audio must stay on this Mac; use 127.0.0.1, localhost, or ::1." >&2
    exit 1
fi

PYTHON="$MOONSHINE_VENV/bin/python"
if [[ ! -x "$PYTHON" ]]; then
    echo "Moonshine virtualenv not found: $MOONSHINE_VENV" >&2
    echo "Run scripts/setup-moonshine-server.sh first." >&2
    exit 1
fi

echo "Starting Moonshine server"
echo "  backend: $MOONSHINE_BACKEND"
echo "  model:   $MOONSHINE_MODEL"
echo "  voice:   $MOONSHINE_LANGUAGE/$MOONSHINE_VOICE_ARCH"
echo "  URL:     http://$MOONSHINE_HOST:$MOONSHINE_PORT/transcribe"

args=(
    "$SCRIPT_DIR/moonshine_server.py"
    --host "$MOONSHINE_HOST"
    --port "$MOONSHINE_PORT"
    --backend "$MOONSHINE_BACKEND"
    --model "$MOONSHINE_MODEL"
    --language "$MOONSHINE_LANGUAGE"
    --voice-arch "$MOONSHINE_VOICE_ARCH"
)

if [[ -n "${LOCAL_WISPR_MOONSHINE_DEVICE:-}" ]]; then
    args+=(--device "$LOCAL_WISPR_MOONSHINE_DEVICE")
fi

if [[ -n "${LOCAL_WISPR_MOONSHINE_DTYPE:-}" ]]; then
    args+=(--torch-dtype "$LOCAL_WISPR_MOONSHINE_DTYPE")
fi

if [[ -n "${LOCAL_WISPR_MOONSHINE_MAX_NEW_TOKENS:-}" ]]; then
    args+=(--max-new-tokens "$LOCAL_WISPR_MOONSHINE_MAX_NEW_TOKENS")
fi

if [[ -n "${LOCAL_WISPR_MOONSHINE_ATTN_IMPLEMENTATION:-}" ]]; then
    args+=(--attn-implementation "$LOCAL_WISPR_MOONSHINE_ATTN_IMPLEMENTATION")
fi

if [[ "${LOCAL_WISPR_MOONSHINE_PRELOAD:-1}" != "1" ]]; then
    args+=(--no-preload)
fi

exec "$PYTHON" "${args[@]}"

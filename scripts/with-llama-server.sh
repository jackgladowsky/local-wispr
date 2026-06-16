#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MODEL="${LOCAL_WISPR_CLEANUP_MODEL:-$APP_SUPPORT/Models/cleanup/cleanup.gguf}"
HOST="${LOCAL_WISPR_LLAMA_SERVER_HOST:-127.0.0.1}"
PORT="${LOCAL_WISPR_LLAMA_SERVER_PORT:-}"
CTX_SIZE="${LOCAL_WISPR_LLAMA_CONTEXT_SIZE:-2048}"
READY_TIMEOUT_SECONDS="${LOCAL_WISPR_LLAMA_READY_TIMEOUT_SECONDS:-60}"
LOG_DIR="${LOCAL_WISPR_LLAMA_SERVER_LOG_DIR:-$ROOT_DIR/.auto/tmp}"

usage() {
    cat <<'EOF'
Usage: scripts/with-llama-server.sh -- COMMAND [ARGS...]

Starts a loopback llama.cpp server with benchmark-tunable env knobs, waits for it,
runs COMMAND with LOCAL_WISPR_LLAMA_SERVER_URL set, then stops the server.

Tunable env vars:
  LOCAL_WISPR_CLEANUP_MODEL
  LOCAL_WISPR_LLAMA_CONTEXT_SIZE
  LOCAL_WISPR_LLAMA_THREADS
  LOCAL_WISPR_LLAMA_THREADS_BATCH
  LOCAL_WISPR_LLAMA_GPU_LAYERS
  LOCAL_WISPR_LLAMA_BATCH_SIZE
  LOCAL_WISPR_LLAMA_UBATCH_SIZE
  LOCAL_WISPR_LLAMA_FLASH_ATTN=1
  LOCAL_WISPR_LLAMA_MLOCK=1
  LOCAL_WISPR_LLAMA_NO_MMAP=1
  LOCAL_WISPR_LLAMA_EXTRA_ARGS="..."
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ "${1:-}" == "--" ]]; then
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Missing command to run under llama-server" >&2
    usage >&2
    exit 2
fi

if [[ "$HOST" != "127.0.0.1" \
    && "$HOST" != "localhost" \
    && "$HOST" != "::1" \
    && "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" != "1" ]]; then
    echo "Refusing to bind llama-server to non-loopback host: $HOST" >&2
    echo "Set LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA=1 only for non-sensitive synthetic runs." >&2
    exit 64
fi

find_executable() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    for candidate in \
        "/opt/homebrew/opt/llama.cpp/bin/$name" \
        "/usr/local/opt/llama.cpp/bin/$name"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

choose_port() {
    if [[ -n "$PORT" ]]; then
        echo "$PORT"
        return 0
    fi

    python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

LLAMA_SERVER="$(find_executable llama-server)" || {
    echo "llama-server not found. Run scripts/setup-local-engines.sh first." >&2
    exit 69
}

if [[ ! -f "$MODEL" ]]; then
    echo "Cleanup model not found: $MODEL" >&2
    echo "Run scripts/setup-local-engines.sh first." >&2
    exit 69
fi

PORT="$(choose_port)"
URL="http://$HOST:$PORT/completion"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/llama-server-$PORT.log"

args=(
    -m "$MODEL"
    --host "$HOST"
    --port "$PORT"
    -c "$CTX_SIZE"
)

if [[ -n "${LOCAL_WISPR_LLAMA_THREADS:-}" ]]; then
    args+=(--threads "$LOCAL_WISPR_LLAMA_THREADS")
fi

if [[ -n "${LOCAL_WISPR_LLAMA_THREADS_BATCH:-}" ]]; then
    args+=(--threads-batch "$LOCAL_WISPR_LLAMA_THREADS_BATCH")
fi

if [[ -n "${LOCAL_WISPR_LLAMA_GPU_LAYERS:-}" ]]; then
    args+=(--n-gpu-layers "$LOCAL_WISPR_LLAMA_GPU_LAYERS")
fi

if [[ -n "${LOCAL_WISPR_LLAMA_BATCH_SIZE:-}" ]]; then
    args+=(-b "$LOCAL_WISPR_LLAMA_BATCH_SIZE")
fi

if [[ -n "${LOCAL_WISPR_LLAMA_UBATCH_SIZE:-}" ]]; then
    args+=(-ub "$LOCAL_WISPR_LLAMA_UBATCH_SIZE")
fi

if [[ "${LOCAL_WISPR_LLAMA_FLASH_ATTN:-0}" == "1" ]]; then
    args+=(--flash-attn on)
fi

if [[ "${LOCAL_WISPR_LLAMA_MLOCK:-0}" == "1" ]]; then
    args+=(--mlock)
fi

if [[ "${LOCAL_WISPR_LLAMA_NO_MMAP:-0}" == "1" ]]; then
    args+=(--no-mmap)
fi

if [[ -n "${LOCAL_WISPR_LLAMA_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=($LOCAL_WISPR_LLAMA_EXTRA_ARGS)
    args+=("${extra_args[@]}")
fi

echo "Starting managed llama-server: $URL" >&2
echo "Log: $LOG_FILE" >&2
"$LLAMA_SERVER" "${args[@]}" >"$LOG_FILE" 2>&1 &
server_pid=$!

cleanup() {
    if kill -0 "$server_pid" >/dev/null 2>&1; then
        kill "$server_pid" >/dev/null 2>&1 || true
        wait "$server_pid" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

ready=0
deadline=$((SECONDS + READY_TIMEOUT_SECONDS))
while [[ $SECONDS -lt $deadline ]]; do
    if ! kill -0 "$server_pid" >/dev/null 2>&1; then
        echo "llama-server exited before becoming ready. Last log lines:" >&2
        tail -40 "$LOG_FILE" >&2 || true
        exit 1
    fi

    if curl -fsS --max-time 5 "$URL" \
        -H 'Content-Type: application/json' \
        -d '{"prompt":"Return only this word: ready","n_predict":8,"temperature":0.1,"cache_prompt":true,"stream":false}' \
        >/dev/null 2>&1; then
        ready=1
        break
    fi

    sleep 1
done

if [[ "$ready" != "1" ]]; then
    echo "llama-server did not become ready within ${READY_TIMEOUT_SECONDS}s. Last log lines:" >&2
    tail -40 "$LOG_FILE" >&2 || true
    exit 1
fi

export LOCAL_WISPR_REWRITE_ENGINE=llama-server
export LOCAL_WISPR_LLAMA_SERVER_URL="$URL"

set +e
"$@"
status=$?
set -e
exit "$status"

#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="$HOME/Library/Application Support/LocalWispr"
MODEL="${LOCAL_WISPR_CLEANUP_MODEL:-$APP_SUPPORT/Models/cleanup/cleanup.gguf}"
HOST="${LOCAL_WISPR_LLAMA_SERVER_HOST:-127.0.0.1}"
PORT="${LOCAL_WISPR_LLAMA_SERVER_PORT:-8080}"
CTX_SIZE="${LOCAL_WISPR_LLAMA_CONTEXT_SIZE:-2048}"

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

LLAMA_SERVER="$(find_executable llama-server)" || {
    echo "llama-server not found. Run scripts/setup-local-engines.sh first." >&2
    exit 69
}

if [[ ! -f "$MODEL" ]]; then
    echo "Cleanup model not found: $MODEL" >&2
    echo "Run scripts/setup-local-engines.sh first." >&2
    exit 69
fi

echo "Starting llama.cpp server"
echo "Model: $MODEL"
echo "URL:   http://$HOST:$PORT/completion"
echo
echo "Launch Local Wispr with:"
echo "LOCAL_WISPR_REWRITE_ENGINE=llama-server LOCAL_WISPR_LLAMA_SERVER_URL=http://$HOST:$PORT/completion scripts/install-app.sh"
echo

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

exec "$LLAMA_SERVER" "${args[@]}"

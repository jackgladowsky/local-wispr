#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export LOCAL_WISPR_REWRITE_BENCH_ITERATIONS="${LOCAL_WISPR_REWRITE_BENCH_ITERATIONS:-5}"
export LOCAL_WISPR_REWRITE_BENCH_WARMUP="${LOCAL_WISPR_REWRITE_BENCH_WARMUP:-1}"
export LOCAL_WISPR_REWRITE_BENCH_ENGINE="${LOCAL_WISPR_REWRITE_BENCH_ENGINE:-production}"
export LOCAL_WISPR_CLEANUP_NUM_PREDICT="${LOCAL_WISPR_CLEANUP_NUM_PREDICT:-9}"
export LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS="${LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS:-1000}"
export LOCAL_WISPR_LLAMA_GPU_LAYERS="${LOCAL_WISPR_LLAMA_GPU_LAYERS:-999}"

if [[ "$LOCAL_WISPR_REWRITE_BENCH_ENGINE" =~ ^(llama-server|production)$ \
    && "${LOCAL_WISPR_MANAGED_LLAMA_SERVER:-1}" == "1" ]]; then
    scripts/with-llama-server.sh -- scripts/benchmark-rewrite-loop.sh --format metrics
else
    scripts/benchmark-rewrite-loop.sh --format metrics
fi

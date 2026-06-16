#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export LOCAL_WISPR_RAW_ITERATIONS="${LOCAL_WISPR_RAW_ITERATIONS:-60}"
export LOCAL_WISPR_RAW_WARMUP="${LOCAL_WISPR_RAW_WARMUP:-8}"
export LOCAL_WISPR_RAW_PROMPT_STYLE="${LOCAL_WISPR_RAW_PROMPT_STYLE:-chatml-filler}"
export LOCAL_WISPR_RAW_N_PREDICT="${LOCAL_WISPR_RAW_N_PREDICT:-${LOCAL_WISPR_CLEANUP_NUM_PREDICT:-38}}"
export LOCAL_WISPR_RAW_TEMPERATURE="${LOCAL_WISPR_RAW_TEMPERATURE:-0}"
export LOCAL_WISPR_RAW_CACHE_PROMPT="${LOCAL_WISPR_RAW_CACHE_PROMPT:-1}"
export LOCAL_WISPR_RAW_STOP_MODE="${LOCAL_WISPR_RAW_STOP_MODE:-chatml}"
export LOCAL_WISPR_LLAMA_GPU_LAYERS="${LOCAL_WISPR_LLAMA_GPU_LAYERS:-999}"
export LOCAL_WISPR_LLAMA_EXTRA_ARGS="${LOCAL_WISPR_LLAMA_EXTRA_ARGS:---parallel 4 --log-disable --spec-type ngram-mod --spec-ngram-mod-n-min 16 --spec-ngram-mod-n-max 32 --spec-ngram-mod-n-match 12}"

if [[ "${LOCAL_WISPR_MANAGED_LLAMA_SERVER:-1}" == "1" ]]; then
    scripts/with-llama-server.sh -- python3 .auto/raw_llama_roundtrip.py
else
    python3 .auto/raw_llama_roundtrip.py
fi

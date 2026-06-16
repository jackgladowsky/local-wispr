#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PATH="$ROOT_DIR/Tests/Fixtures/rewrite-benchmark.json"
ITERATIONS="${LOCAL_WISPR_REWRITE_BENCH_ITERATIONS:-3}"
WARMUP="${LOCAL_WISPR_REWRITE_BENCH_WARMUP:-1}"
ENGINE="${LOCAL_WISPR_REWRITE_BENCH_ENGINE:-production}"
FORMAT="metrics"
STRICT=0

usage() {
    cat <<'EOF'
Usage: scripts/benchmark-rewrite-loop.sh [options]

Runs the text-only rewrite/cleanup replay benchmark used by the autonomous
optimization loop. The benchmark emits METRIC lines by default.

Options:
  --fixture PATH       fixture file (default: Tests/Fixtures/rewrite-benchmark.json)
  --iterations N       measured iterations per fixture (default: $LOCAL_WISPR_REWRITE_BENCH_ITERATIONS or 3)
  --warmup N           warmup iterations per fixture (default: $LOCAL_WISPR_REWRITE_BENCH_WARMUP or 1)
  --engine MODE        production | rule-based | llama-server (default: production)
  --format FORMAT      metrics | json | table (default: metrics)
  --strict             exit nonzero if any fixture quality check fails
  -h, --help           show this help

Useful llama-server run:
  scripts/start-llama-server.sh
  scripts/benchmark-rewrite-loop.sh --engine llama-server --format table
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixture)
            FIXTURE_PATH="${2:?missing path for --fixture}"
            shift 2
            ;;
        --iterations)
            ITERATIONS="${2:?missing value for --iterations}"
            shift 2
            ;;
        --warmup)
            WARMUP="${2:?missing value for --warmup}"
            shift 2
            ;;
        --engine)
            ENGINE="${2:?missing value for --engine}"
            shift 2
            ;;
        --format)
            FORMAT="${2:?missing value for --format}"
            shift 2
            ;;
        --strict)
            STRICT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cd "$ROOT_DIR"

swift build -c release --product LocalWisprRewriteBench >/dev/null

args=(
    "--fixture" "$FIXTURE_PATH"
    "--iterations" "$ITERATIONS"
    "--warmup" "$WARMUP"
    "--engine" "$ENGINE"
    "--format" "$FORMAT"
)

if [[ "$STRICT" == "1" ]]; then
    args+=("--strict")
fi

"$ROOT_DIR/.build/release/LocalWisprRewriteBench" "${args[@]}"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---artifact-scan-only}"

usage() {
    cat <<'EOF'
Usage: scripts/preflight-autoresearch.sh [--artifact-scan-only|--before-launch]

Checks safety guardrails for Local Wispr autonomous rewrite optimization.
--artifact-scan-only validates ignore/denylist/endpoint rules in the current tree.
--before-launch also requires a clean hidden experiment worktree.
EOF
}

case "$MODE" in
    --artifact-scan-only|--before-launch) ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown mode: $MODE" >&2
        usage >&2
        exit 2
        ;;
esac

cd "$ROOT_DIR"

fail() {
    echo "preflight failed: $*" >&2
    exit 1
}

check_loopback_url() {
    local name="$1"
    local value="$2"

    [[ -z "$value" ]] && return 0
    [[ "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" == "1" ]] && return 0

    python3 - "$name" "$value" <<'PY'
import sys
from urllib.parse import urlparse

name, value = sys.argv[1], sys.argv[2]
parsed = urlparse(value)
host = (parsed.hostname or "").lower()
allowed = {"127.0.0.1", "localhost", "::1"}
if host not in allowed:
    print(f"{name} must be loopback unless LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA=1: {value}", file=sys.stderr)
    sys.exit(1)
PY
}

check_loopback_url LOCAL_WISPR_LLAMA_SERVER_URL "${LOCAL_WISPR_LLAMA_SERVER_URL:-}"
check_loopback_url LOCAL_WISPR_LLAMA_SERVER_ENDPOINT "${LOCAL_WISPR_LLAMA_SERVER_ENDPOINT:-}"

if [[ "${LOCAL_WISPR_LLAMA_SERVER_HOST:-127.0.0.1}" != "127.0.0.1" \
    && "${LOCAL_WISPR_LLAMA_SERVER_HOST:-}" != "localhost" \
    && "${LOCAL_WISPR_LLAMA_SERVER_HOST:-}" != "::1" \
    && "${LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA:-0}" != "1" ]]; then
    fail "LOCAL_WISPR_LLAMA_SERVER_HOST must be loopback unless LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA=1"
fi

for path in \
    progress.md \
    opt-loop/runs/example.jsonl \
    opt-loop/private/example.json \
    .auto/log.jsonl \
    .auto/tmp/llama-server.log \
    scratch.wav \
    scratch.caf \
    model.gguf \
    model.bin \
    signing.p12 \
    timings.csv \
    benchmark.log; do
    git check-ignore -q "$path" || fail "$path is not ignored"
done

denylist_regex='\.(wav|caf|aiff|m4a|mp3|flac|gguf|bin|p12|log|csv)$'
tracked_hits="$(git ls-files | grep -Ei "$denylist_regex" || true)"
if [[ -n "$tracked_hits" ]]; then
    fail "denylisted tracked artifact(s): $tracked_hits"
fi

untracked_hits="$(git ls-files --others --exclude-standard | grep -Ei "$denylist_regex" || true)"
if [[ -n "$untracked_hits" ]]; then
    fail "denylisted untracked artifact(s): $untracked_hits"
fi

if [[ "$MODE" == "--before-launch" ]]; then
    worktree_root="$(git rev-parse --show-toplevel)"
    case "$worktree_root" in
        "$HOME/dev/.worktrees/local-wispr/"*) ;;
        *) fail "autoresearch launch must happen from a hidden worktree under ~/dev/.worktrees/local-wispr/" ;;
    esac

    branch="$(git branch --show-current)"
    case "$branch" in
        experiment/*|autoresearch/*) ;;
        *) fail "autoresearch branch should start with experiment/ or autoresearch/; got $branch" ;;
    esac

    dirty="$(git status --porcelain --untracked-files=all)"
    if [[ -n "$dirty" ]]; then
        fail "worktree must be clean before launch"
    fi
fi

echo "autoresearch preflight passed ($MODE)"

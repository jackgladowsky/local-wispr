#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/preflight-autoresearch.sh --artifact-scan-only >/tmp/local-wispr-autoresearch-preflight.log
scripts/benchmark-rewrite-loop.sh --engine rule-based --strict >/tmp/local-wispr-rewrite-checks.log
swift test >/tmp/local-wispr-swift-test.log
git diff --check

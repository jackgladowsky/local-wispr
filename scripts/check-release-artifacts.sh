#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$ROOT_DIR/dist/release}"

if [[ ! -e "$TARGET" ]]; then
    echo "Release artifact path not found: $TARGET" >&2
    exit 1
fi

failures=0
while IFS= read -r path; do
    rel="${path#$ROOT_DIR/}"
    lower_rel="$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')"
    base="$(basename "$rel")"
    lower_base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"

    case "$lower_rel" in
        *"/.auto/"*|*.auto/*|*"/opt-loop/"*|opt-loop/*|*localwisprrewritebench*|*localwisprbench*|*rewrite-benchmark*|*fixtures*)
            echo "Forbidden release artifact path: $rel" >&2
            failures=1
            continue
            ;;
    esac

    case "$lower_rel" in
        *"/local wispr.app/contents/resources/moonshinemodels/"*"/tokenizer.bin"|*"/local wispr.app/contents/resources/moonshinemodels/"*.ort)
            continue
            ;;
    esac

    case "$lower_rel" in
        *.wav|*.caf|*.aiff|*.m4a|*.mp3|*.flac|*.gguf|*.bin|*.ort|*.p12|*.log|*.csv)
            echo "Forbidden release artifact extension: $rel" >&2
            failures=1
            continue
            ;;
    esac

    case "$lower_base" in
        localwispr-*-macos.dmg|localwispr-*-macos.zip|sha256sums.txt)
            continue
            ;;
        *.dmg|*.zip)
            echo "Unexpected release archive name: $rel" >&2
            failures=1
            ;;
    esac
done < <(find "$TARGET" -mindepth 1 -print)

if [[ "$failures" != "0" ]]; then
    exit 1
fi

echo "Release artifact scan passed: $TARGET"

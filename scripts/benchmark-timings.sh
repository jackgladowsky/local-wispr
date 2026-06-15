#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="$HOME/Library/Logs/LocalWispr/mock-flow.log"
LAST=""
CSV=0

usage() {
    cat <<'EOF'
Usage: scripts/benchmark-timings.sh [--log PATH] [--last N] [--csv]

Summarize Local Wispr pipeline timings from the local timing log.
Default log: ~/Library/Logs/LocalWispr/mock-flow.log
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)
            LOG_PATH="${2:?missing path for --log}"
            shift 2
            ;;
        --last)
            LAST="${2:?missing count for --last}"
            shift 2
            ;;
        --csv)
            CSV=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            LOG_PATH="$1"
            shift
            ;;
    esac
done

python3 - "$LOG_PATH" "$LAST" "$CSV" <<'PY'
import csv
import math
import pathlib
import re
import shlex
import statistics
import sys

log_path = pathlib.Path(sys.argv[1]).expanduser()
last = int(sys.argv[2]) if sys.argv[2] else None
csv_mode = sys.argv[3] == "1"

if not log_path.exists():
    print(f"Timing log not found: {log_path}", file=sys.stderr)
    sys.exit(1)

line_pattern = re.compile(r"^\[(?P<timestamp>[^\]]+)\]\s+(?P<body>.*)$")
rows = []
errors = []

for line in log_path.read_text(errors="replace").splitlines():
    match = line_pattern.match(line)
    if not match:
        continue

    row = {"timestamp": match.group("timestamp")}
    try:
        tokens = shlex.split(match.group("body"))
    except ValueError:
        continue

    for token in tokens:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        row[key] = value

    if row.get("result") == "error":
        errors.append(row)
    elif "session" in row:
        rows.append(row)

if last:
    rows = rows[-last:]

metrics = [
    "total_session_ms",
    "hotkey_to_recording_ms",
    "mic_permission_ms",
    "audio_start_ms",
    "target_capture_ms",
    "recording_ms",
    "release_to_output_ms",
    "audio_stop_ms",
    "stt_ms",
    "rewrite_ms",
    "insert_ms",
]

legacy_metrics = ["release_to_output_ms", "stt_ms", "rewrite_ms"]

def as_float(value):
    if value in (None, "", "n/a"):
        return None
    try:
        f = float(value)
    except ValueError:
        return None
    if math.isnan(f) or math.isinf(f):
        return None
    return f

def percentile(values, q):
    values = sorted(values)
    if not values:
        return None
    index = (len(values) - 1) * q
    low = math.floor(index)
    high = min(low + 1, len(values) - 1)
    frac = index - low
    return values[low] * (1 - frac) + values[high] * frac

def fmt(value):
    return "n/a" if value is None else f"{value:.1f}"

if csv_mode:
    writer = csv.DictWriter(
        sys.stdout,
        fieldnames=["timestamp", "session", "result", "mode", "stt_engine", "rewrite_engine", "cleanup_engine_used"] + metrics
    )
    writer.writeheader()
    for row in rows:
        writer.writerow({key: row.get(key, "") for key in writer.fieldnames})
    sys.exit(0)

print("Local Wispr pipeline benchmark")
print(f"Log: {log_path}")
detailed_rows = [
    row for row in rows
    if as_float(row.get("audio_stop_ms")) is not None or as_float(row.get("insert_ms")) is not None
]

print(f"Successful sessions analyzed: {len(rows)}")
print(f"Detailed stage sessions: {len(detailed_rows)}")
print(f"Error sessions in log: {len(errors)}")
if last:
    print(f"Window: last {last} successful sessions")
print()

if not rows:
    print("No successful timing rows found yet. Run a dictation or Simulate Dictation, then retry.")
    sys.exit(0)

if detailed_rows and len(detailed_rows) < len(rows):
    print("Note: this log mixes legacy rows and detailed stage rows; stage breakdown uses detailed rows only.")

print()
print(f"{'metric':<26} {'n':>4} {'avg':>9} {'median':>9} {'p90':>9} {'p95':>9} {'min':>9} {'max':>9}")
print("-" * 86)
for metric in metrics:
    values = [as_float(row.get(metric)) for row in rows]
    values = [value for value in values if value is not None]
    if not values and metric not in legacy_metrics:
        continue
    print(
        f"{metric:<26} {len(values):>4} "
        f"{fmt(statistics.mean(values) if values else None):>9} "
        f"{fmt(statistics.median(values) if values else None):>9} "
        f"{fmt(percentile(values, 0.90)):>9} "
        f"{fmt(percentile(values, 0.95)):>9} "
        f"{fmt(min(values) if values else None):>9} "
        f"{fmt(max(values) if values else None):>9}"
    )

stage_metrics = ["audio_stop_ms", "stt_ms", "rewrite_ms", "insert_ms"]
stage_rows = detailed_rows if detailed_rows else rows
stage_avgs = {}
for metric in stage_metrics:
    values = [as_float(row.get(metric)) for row in stage_rows]
    values = [value for value in values if value is not None]
    if values:
        stage_avgs[metric] = statistics.mean(values)

release_values = [as_float(row.get("release_to_output_ms")) for row in stage_rows]
release_values = [value for value in release_values if value is not None]
if release_values and stage_avgs:
    release_avg = statistics.mean(release_values)
    print()
    label = "Average post-release bottleneck share"
    if detailed_rows:
        label += f" (detailed rows n={len(detailed_rows)})"
    print(label + ":")
    for metric, value in sorted(stage_avgs.items(), key=lambda item: item[1], reverse=True):
        share = value / release_avg * 100 if release_avg else 0
        print(f"- {metric:<16} {value:>7.1f} ms  {share:>5.1f}% of release_to_output")

slowest = sorted(
    rows,
    key=lambda row: as_float(row.get("release_to_output_ms")) or -1,
    reverse=True,
)[:5]

print()
print("Slowest successful sessions:")
def ms_value(row, key):
    value = row.get(key, "n/a")
    return value if value == "n/a" else f"{value}ms"

for row in slowest:
    release = ms_value(row, "release_to_output_ms")
    stt = ms_value(row, "stt_ms")
    rewrite = ms_value(row, "rewrite_ms")
    insert = ms_value(row, "insert_ms")
    mode = row.get("mode", "unknown")
    result = row.get("result", "unknown")
    session = row.get("session", "unknown")[:8]
    print(
        f"- {row.get('timestamp', '')} {session} mode={mode} result={result} "
        f"release={release} stt={stt} rewrite={rewrite} insert={insert}"
    )
PY

# Autoresearch: Local Wispr rewrite loop latency

## Objective
Optimize Local Wispr's local rewrite/cleanup loop for lower post-STT latency while preserving dictated meaning and local-first privacy. The primary target is the text cleanup path after `Transcript` is available: prompt construction, local rule routing, llama-server request shape, generation budget, fallback behavior, and instrumentation.

## Metrics
- **Primary**: `objective_error` (lower is better) from `scripts/benchmark-rewrite-loop.sh`. It heavily penalizes failed cases and quality loss before latency.
- **Latency target once quality is clean**: `rewrite_ms_p95` (milliseconds, lower is better).
- **Secondary**: `rewrite_ms_median`, `rewrite_ms_avg`, `quality_score`, `failed_cases`, `fallback_runs`, `llama_runs`, `local_cleanup_runs`, `total_runs`, `fixture_count`.
- **Correctness gate**: `failed_cases` must become/remain `0` and `quality_score` must become/remain `1.000` on the replay fixture set. For LLM-focused runs, `llama_runs` must be nonzero so the loop does not optimize only the local fallback.

## How to Run

```sh
./.auto/measure.sh
```

The measure script builds `LocalWisprRewriteBench`, starts a managed loopback `llama-server` by default, replays text-only cleanup fixtures from `Tests/Fixtures/rewrite-benchmark.json`, targets the llama-server path, and emits `METRIC name=value` lines. This means server-side parameters are part of the optimization surface.

Useful variants:

```sh
# Human-readable local fallback baseline
scripts/benchmark-rewrite-loop.sh --engine rule-based --format table

# Managed llama-server path with tunable server params
LOCAL_WISPR_LLAMA_CONTEXT_SIZE=1024 \
LOCAL_WISPR_LLAMA_THREADS=4 \
LOCAL_WISPR_LLAMA_BATCH_SIZE=128 \
  ./.auto/measure.sh

# Manually managed llama-server path, when intentionally desired
scripts/start-llama-server.sh
LOCAL_WISPR_MANAGED_LLAMA_SERVER=0 \
LOCAL_WISPR_REWRITE_BENCH_ENGINE=llama-server \
  scripts/benchmark-rewrite-loop.sh --format table

# Stricter quality gate for checks
scripts/benchmark-rewrite-loop.sh --strict
```

## Files in Scope
- `Sources/LocalWisprCore/Engines/CleanupPrompt.swift` — prompt text, local-vs-LLM routing heuristics.
- `Sources/LocalWisprCore/Engines/EngineRegistry.swift` — production rewrite engine selection and fallback composition.
- `Sources/LocalWisprCore/Engines/LlamaServerRewriteEngine.swift` — llama-server request payload, prompt cache, timeout, decoding.
- `Sources/LocalWisprCore/Engines/RuleBasedRewriteEngine.swift` — fast local cleanup fallback.
- `Sources/LocalWisprCore/Benchmarking/RewriteBenchmark.swift` — replay harness, quality checks, metric schema.
- `Sources/LocalWisprRewriteBench/main.swift` — CLI wrapper for the replay harness.
- `Tests/Fixtures/rewrite-benchmark.json` — synthetic text-only replay fixtures.
- `Tests/LocalWisprCoreTests/*Rewrite*`, `*CleanupPrompt*`, `*RewriteBenchmark*` — focused tests.
- `scripts/benchmark-rewrite-loop.sh`, `scripts/with-llama-server.sh`, `.auto/measure.sh`, `.auto/checks.sh` — optimization loop entry points.
- `README.md` and `docs/llm-optimization-loop.md` — user-facing docs if behavior or commands change.

## Off Limits
- Do not commit raw audio recordings, private dictation text, secrets, certificates, API keys, or notary credentials.
- Do not weaken privacy/local-first defaults or make cloud services part of the default loop.
- Do not remove release/package/permission stability behavior while optimizing rewrite latency.
- Do not optimize only the synthetic fixture if it makes obvious real dictation cleanup worse.

## Constraints
- Keep the replay fixture set text-only and synthetic unless Jack explicitly approves adding non-sensitive fixtures.
- Keep `swift test` passing.
- Keep `git diff --check` clean.
- Run `scripts/preflight-autoresearch.sh --before-launch` from a clean hidden experiment worktree before a long-running loop.
- Keep llama-server benchmark endpoints and binds loopback-only unless Jack explicitly approves a non-sensitive synthetic override.
- Server-side knobs are in scope for optimization via `scripts/with-llama-server.sh`: cleanup model path, context size, threads, batch/ubatch size, GPU layers, flash attention, mlock/mmap, and `LOCAL_WISPR_LLAMA_EXTRA_ARGS`.
- Prefer simple, measurable changes. If a change improves latency but drops `quality_score` below `1.000`, increases `failed_cases`, or turns an LLM-focused run into only `local_cleanup_runs`, revert or fix before keeping it.
- Record useful learnings in this file or `.auto/ideas.md` so future agents do not repeat failed experiments.

## What's Been Tried
- 2026-06-15: Backbone created: text replay fixtures, developer-only `LocalWisprRewriteBench` executable target, managed llama-server wrapper, `scripts/benchmark-rewrite-loop.sh`, `.auto/measure.sh`, `.auto/checks.sh`, preflight/release guardrails, ignore guardrails, temporary audio cleanup, actual cleanup-engine metrics, and docs. No optimization experiments have been run yet.
- 2026-06-15 iteration: Added managed llama-server measurement so server params are optimized inside `.auto/measure.sh`. Baseline direct LLM was quality-failing (`objective_error` ~4.1M, `quality_score=0`, `failed_cases=4`). ChatML-style prompt + deterministic output polish raised quality. Routing local-safe plain/list/long fixtures through Basic Local Cleanup while keeping email-subject on llama-server made quality clean and reduced p95 dramatically. Kept defaults: production benchmark mode, `LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS=1000`, `LOCAL_WISPR_CLEANUP_NUM_PREDICT=9`, full GPU layers. Current verified `.auto/measure.sh` during merge prep: `objective_error=41.992`, `quality_score=1.000`, `failed_cases=0`, `rewrite_ms_p95=41.992`, `llama_runs=5`, `local_cleanup_runs=15`.

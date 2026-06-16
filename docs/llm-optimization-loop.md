# LLM/rewrite optimization loop

Local Wispr's cleanup path is now set up for repeatable autonomous optimization without storing audio or private dictation text in git. Full-pipeline observational runs can be isolated with `LOCAL_WISPR_TIMING_LOG=/path/to/run.log`, but the primary loop remains text-only rewrite replay.

## What is measured

The optimization backbone focuses on the rewrite/cleanup loop after STT has produced a `Transcript`:

```text
Transcript -> CleanupPrompt routing -> rule-based cleanup or llama-server cleanup -> CleanedText
```

The benchmark intentionally uses synthetic text fixtures rather than audio. Full app timing is still available through `scripts/benchmark-timings.sh`, but text replay gives fast, repeatable signal for prompt/model-routing experiments.

## Commands

Run the replay benchmark and emit `METRIC` lines:

```sh
scripts/benchmark-rewrite-loop.sh
```

Human-readable table:

```sh
scripts/benchmark-rewrite-loop.sh --format table
```

Rule-only fallback baseline:

```sh
scripts/benchmark-rewrite-loop.sh --engine rule-based --format table
```

llama-server path with a manually managed server:

```sh
scripts/start-llama-server.sh
LOCAL_WISPR_REWRITE_BENCH_ENGINE=llama-server scripts/benchmark-rewrite-loop.sh --format table
```

Autonomous-loop entrypoint. By default this starts a managed loopback llama-server and runs production cleanup routing with benchmark-specific overrides, so server launch parameters, request params, prompt behavior, and local-vs-LLM routing can be optimized together:

```sh
./.auto/measure.sh
```

Current benchmark defaults route local-safe text through Basic Local Cleanup, keep structured email-subject cleanup on llama-server, set `LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS=1000`, cap cleanup generation at 9 tokens, and require nonzero `llama_runs`. These are optimization-loop defaults, not necessarily app launch defaults. Set `LOCAL_WISPR_MANAGED_LLAMA_SERVER=0` only when you intentionally want to measure against an already-running external server.

Correctness/quality checks. These run the rule-based smoke path plus safety scans/tests and do not require llama-server:

```sh
./.auto/checks.sh
```

## Metrics

`LocalWisprRewriteBench` emits:

- `rewrite_ms_avg`
- `rewrite_ms_median`
- `rewrite_ms_p95`
- `objective_error` (lower is better; heavily penalizes failed cases/quality before latency)
- `quality_score`
- `failed_cases`
- `fallback_runs`
- `llama_runs`
- `local_cleanup_runs`
- `total_runs`
- `fixture_count`

The intended primary optimization target for autonomous runs is `objective_error` (lower is better), which prioritizes `failed_cases=0` and `quality_score=1.000` before latency. Once quality is clean, optimize `rewrite_ms_p95` with nonzero `llama_runs` for LLM-focused runs.

## Fixture strategy

Fixtures live in `Tests/Fixtures/rewrite-benchmark.json` and are synthetic text only. Each case contains:

- `id`
- `transcript`
- `expectedContains`
- `forbiddenContains`
- optional `notes`

Keep fixtures short, reviewable, and privacy-safe. Do not add raw user dictation or audio clips unless explicitly approved and known non-sensitive.

## Files to inspect during optimization

- `Sources/LocalWisprCore/Engines/CleanupPrompt.swift`
- `Sources/LocalWisprCore/Engines/LlamaServerRewriteEngine.swift`
- `Sources/LocalWisprCore/Engines/EngineRegistry.swift`
- `Sources/LocalWisprCore/Engines/RuleBasedRewriteEngine.swift`
- `Sources/LocalWisprCore/Benchmarking/RewriteBenchmark.swift`
- `Sources/LocalWisprRewriteBench/main.swift`
- `Tests/Fixtures/rewrite-benchmark.json`
- `.auto/prompt.md`
- `scripts/preflight-autoresearch.sh`
- `scripts/check-release-artifacts.sh`
- `scripts/with-llama-server.sh`

## Guardrails

- Preserve local-first behavior by default.
- Keep raw audio/private dictation out of git.
- Keep `swift test` and `git diff --check` passing.
- Do not keep a latency improvement that fails the replay quality gate.
- Run `scripts/preflight-autoresearch.sh --before-launch` from a clean hidden experiment worktree before a long-running autoresearch loop.
- Llama benchmark endpoints and managed server binds must be loopback (`127.0.0.1`, `localhost`, or `::1`) unless explicitly overridden for a non-sensitive synthetic run.
- Release packaging scans for `.auto/`, `opt-loop/`, benchmark binaries, logs, audio, models, and cert artifacts.
- Record durable optimization learnings in `.auto/prompt.md`, `.auto/ideas.md`, and `Projects/Local Wispr/` in Obsidian when decisions change.

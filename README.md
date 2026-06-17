# Local Wispr

Local Wispr is a native macOS menu bar app for fast, fully local dictation. Hold a global hotkey, speak naturally, release, and Local Wispr transcribes, lightly rewrites, and inserts polished text into the active app.

The project is currently an early macOS prototype focused on proving the end-to-end local dictation loop: reliable capture, local speech-to-text, local cleanup, safe paste insertion, and smooth macOS permission handling.

## Highlights

- **Local-first pipeline**: microphone audio, transcription, cleanup, and timing logs stay on the machine.
- **Native macOS UX**: menu bar app, no Dock icon, floating status panel, SwiftUI settings.
- **Hold-to-dictate hotkey**: press and hold `Control` + `Option` + `Space`; release to process.
- **Local speech-to-text**: `whisper.cpp` CLI adapter with a default local Whisper model.
- **Local cleanup**: optional `llama.cpp` rewrite model with a basic local cleanup fallback.
- **Safe insertion**: clipboard-preserving paste with focus checks and secure-field avoidance.
- **Permission-resilient paste helper**: a stable helper app can own Accessibility permission across main-app rebuilds.

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode Command Line Tools
- Homebrew, for the local engine setup script
- Microphone permission for real dictation
- Accessibility permission for automatic paste; without it, Local Wispr copies output for manual `Command-V`

## Quick Start

```sh
git clone https://github.com/jackgladowsky/local-wispr.git
cd local-wispr

scripts/setup-local-engines.sh
scripts/install-app.sh
```

`install-app.sh` builds, installs, and launches:

```text
~/Applications/Local Wispr.app
~/Applications/Local Wispr Paste Helper.app
```

Open Local Wispr from the menu bar, finish permissions in **Settings**, then hold `Control` + `Option` + `Space` to dictate.

## Permissions

macOS permissions are part of the product flow, not an afterthought. Local Wispr separates required and optional permissions so the app remains usable even when automatic paste is not approved yet.

| Permission | Required | Purpose | Fallback |
| --- | --- | --- | --- |
| Microphone | Yes | Captures dictation audio locally | Real dictation is unavailable |
| Main App Accessibility | Optional | Allows the main app to post paste keystrokes | Output is copied to clipboard |
| Paste Helper Accessibility | Optional | Stable automatic paste across rebuilds | Output is copied to clipboard |

The recommended development path is to approve **Local Wispr Paste Helper** for Accessibility. The helper is intentionally kept separate from the main app so macOS trust records are less likely to break every time the main app is rebuilt.

If permissions get stale or macOS shows a checkbox as enabled while the app is still not trusted, reset TCC records:

```sh
scripts/reset-permissions.sh
```

## Local Engine Setup

Install `whisper.cpp`, download the default Whisper model, install `llama.cpp`, and download the default local cleanup model:

```sh
scripts/setup-local-engines.sh
```

The default engine locations are:

```text
whisper-cli:          /opt/homebrew/bin/whisper-cli or PATH
Whisper model:        ~/Library/Application Support/LocalWispr/Models/whisper/ggml-base.en.bin
llama.cpp cleanup model: ~/Library/Application Support/LocalWispr/Models/cleanup/cleanup.gguf
```

Check engine status:

```sh
scripts/check-local-engines.sh
```

Smoke-test local engine responses:

```sh
scripts/smoke-local-engines.sh
```

`llama.cpp` cleanup is optional. To install only the speech-to-text path and use the built-in cleanup fallback:

```sh
LOCAL_WISPR_WITH_LLAMA_CPP=0 scripts/setup-local-engines.sh
```

Latency-oriented cleanup knobs:

```sh
# Skip the LLM for short/simple transcripts and use local rules instead. Default: 120 chars.
LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS=120

# Cap LLM cleanup time before falling back to local rules. Default: 650 ms.
LOCAL_WISPR_LLM_CLEANUP_BUDGET_MS=650

# Override cleanup generation length. App default is dynamic (38–192 tokens).
# The synthetic rewrite benchmark uses 9 tokens for the current fixture mix.
LOCAL_WISPR_CLEANUP_NUM_PREDICT=128
```

For lower cleanup latency, run a warmed `llama.cpp` server and launch Local Wispr with:

```sh
LOCAL_WISPR_LLAMA_GPU_LAYERS=999 \
LOCAL_WISPR_LLAMA_EXTRA_ARGS="--parallel 4 --log-disable --spec-type ngram-mod --spec-ngram-mod-n-min 16 --spec-ngram-mod-n-max 32 --spec-ngram-mod-n-match 12" \
  scripts/start-llama-server.sh

LOCAL_WISPR_REWRITE_ENGINE=llama-server \
LOCAL_WISPR_LLAMA_SERVER_URL=http://127.0.0.1:8080/completion \
  scripts/install-app.sh
```

Without a running `llama-server`, Local Wispr uses Basic Local Cleanup instead of launching a slow per-request model process. Cleanup server URLs must be loopback (`127.0.0.1`, `localhost`, or `::1`) unless `LOCAL_WISPR_ALLOW_NON_LOOPBACK_LLAMA=1` is explicitly set for a non-sensitive synthetic run.

After changing engines or environment variables, choose **Reload Engines** from the Local Wispr menu or relaunch the app from the same environment.

## Experimental Streaming STT

Local Wispr includes an off-by-default streaming/speculative STT path for latency experiments. The normal batch recorder remains the default.

```sh
LOCAL_WISPR_EXPERIMENTAL_STREAMING=1 scripts/install-app.sh
```

When enabled, the app keeps the normal full-session recording for fallback while also chunking microphone audio. Finalized chunks are transcribed and lightly cleaned while you are still holding the hotkey. On release, Local Wispr assembles the ordered speculative transcript, then either runs a final cohesion cleanup or, for the fastest experimental path, skips final cleanup:

```sh
LOCAL_WISPR_EXPERIMENTAL_STREAMING=1 \
LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP=1 \
  scripts/install-app.sh
```

Tuning knobs:

```sh
LOCAL_WISPR_STREAMING_CHUNK_SECONDS=2.5
LOCAL_WISPR_STREAMING_MIN_CHUNK_SECONDS=0.25
LOCAL_WISPR_STREAMING_CHUNK_GRACE_SECONDS=2.0
```

Latest local timing evidence from `~/Library/Logs/LocalWispr/mock-flow.log`: experimental streaming improved average STT from about `238.7 ms` in recent main rows to about `191.1 ms`; the no-final-cleanup experimental path averaged about `187.1 ms` STT and `345.4 ms` release-to-output over the latest 5 rows. Treat this path as experimental until accuracy and longer-dictation coverage are stronger. See [`docs/streaming-stt-experiment.md`](docs/streaming-stt-experiment.md).

## Build and Install

Build the Swift package:

```sh
swift build
```

Build app bundles into `dist/`:

```sh
scripts/build-app.sh
```

Install to a stable user Applications directory:

```sh
scripts/install-app.sh
```

Avoid authorizing app bundles directly from `dist/`. Rebuilds can make macOS treat those bundles as changed apps, which often breaks Accessibility trust.

By default, `install-app.sh` preserves an existing paste helper to keep its Accessibility permission stable. When the helper bundle version increases, the script updates it and resets Accessibility/PostEvent/ListenEvent TCC records to avoid the stale checked-but-untrusted macOS state. You will need to approve **Local Wispr Paste Helper** again after that kind of helper update.

For development, you can force a clean Accessibility reset on every install:

```sh
LOCAL_WISPR_RESET_ACCESSIBILITY_ON_INSTALL=1 scripts/install-app.sh
```

To intentionally replace the helper even when the installed version is current:

```sh
LOCAL_WISPR_UPDATE_HELPER=1 scripts/install-app.sh
```

For smoother permission behavior, sign with a stable code signing identity:

```sh
LOCAL_WISPR_CODESIGN_IDENTITY="Apple Development: Your Name (...)" scripts/build-app.sh
scripts/install-app.sh
```

Inspect signing state:

```sh
scripts/signing-status.sh
```

## Release Packaging

Build release-ready DMG/ZIP assets locally:

```sh
scripts/package-release.sh
```

Assets are written to `dist/release/` with checksums. GitHub releases are packaged by `.github/workflows/release.yml`, which runs tests, builds the app bundles, creates a DMG/ZIP, optionally notarizes the DMG, and uploads assets to the release.

Public releases should use protected `vMAJOR.MINOR.PATCH` tags plus Developer ID signing/notarization secrets in the GitHub `release` environment. See [`docs/release.md`](docs/release.md).

## Benchmarking

Local Wispr writes one timing line per dictation session to:

```text
~/Library/Logs/LocalWispr/mock-flow.log
```

For isolated benchmark runs, launch with `LOCAL_WISPR_TIMING_LOG=/path/to/run.log`.

Summarize the full pipeline:

```sh
scripts/benchmark-timings.sh
```

Limit the summary to the most recent successful sessions:

```sh
scripts/benchmark-timings.sh --last 20
```

Compare default and experimental streaming modes:

```sh
scripts/benchmark-timings.sh --mode real --last 20
scripts/benchmark-timings.sh --mode real-streaming-experimental --last 20
```

Export raw timing rows as CSV:

```sh
scripts/benchmark-timings.sh --csv > timings.csv
```

Replay the text-only rewrite/cleanup benchmark used for autonomous optimization:

```sh
scripts/benchmark-rewrite-loop.sh --format table
./.auto/measure.sh
```

`.auto/measure.sh` manages a loopback `llama-server` by default for LLM-focused runs, so server knobs such as context size, threads, GPU layers, batch size, model path, and extra llama.cpp args can be part of optimization.

The rewrite benchmark emits `METRIC` lines for `objective_error`, `rewrite_ms_p95`, `rewrite_ms_median`, `quality_score`, `failed_cases`, `fallback_runs`, and cleanup-engine counts. It uses synthetic text fixtures in `Tests/Fixtures/rewrite-benchmark.json`; see [`docs/llm-optimization-loop.md`](docs/llm-optimization-loop.md).

Latest local verification (`./.auto/measure.sh`, managed loopback llama-server, 4 synthetic fixtures × 5 measured iterations, 1 warmup):

| Metric | Value |
| --- | ---: |
| `objective_error` | 41.992 |
| `rewrite_ms_p95` | 41.992 ms |
| `rewrite_ms_median` | 1.585 ms |
| `rewrite_ms_avg` | 11.283 ms |
| `quality_score` | 1.000 |
| `failed_cases` | 0 |
| `llama_runs` / `local_cleanup_runs` | 5 / 15 |

Direct raw `llama-server` roundtrip benchmark, excluding STT/routing/insertion overhead:

```sh
./.auto/measure-raw-llama.sh
```

Latest local verification (`chatml-filler`, `n_predict=38`, `temperature=0`, `cache_prompt=1`, ngram speculative decoding, 60 measured / 8 warmup):

| Raw llama-server phase | Avg | Median | P95 | Invalid |
| --- | ---: | ---: | ---: | ---: |
| Repeated/cache-friendly | 30.321 ms | 30.283 ms | 30.858 ms | 0 |
| Varied cleanup prompts | 53.549 ms | 48.613 ms | 80.327 ms | 0 |

New timing logs include stage-level fields such as `hotkey_to_recording_ms`, `audio_start_ms`, `audio_stop_ms`, `stt_ms`, `rewrite_ms`, `insert_ms`, `cleanup_engine_used`, and `release_to_output_ms`. The most important user-facing metric is `release_to_output_ms`: time from releasing the hotkey to pasted/copied output.

## Architecture

```text
LocalWispr.app
├─ AppDelegate / menu bar lifecycle
├─ HotkeyController          Carbon global hold hotkey
├─ AudioCapture              AVFoundation microphone capture, optional chunking
├─ DictationSession          recording → STT → cleanup → insertion orchestration
├─ SpeculativeDictation      off-by-default chunk STT/cleanup experiment
├─ EngineRegistry            STT and rewrite engine selection
├─ InsertionController       clipboard-safe paste and fallback copy behavior
├─ Settings                  permissions, engine status, logs, model paths
└─ TimingLogger              local latency/debug traces

Local Wispr Paste Helper.app
└─ Owns stable Accessibility trust for synthetic paste events across rebuilds
```

## Privacy

Local Wispr is designed to run without cloud transcription or analytics.

- Audio is captured locally and sent to local engines only.
- The default Whisper model is stored under Application Support.
- Timing/debug logs are written locally to `~/Library/Logs/LocalWispr/mock-flow.log`.
- Temporary full-session and streaming chunk audio files are removed after processing/cancel/failure.
- Cleanup uses Basic Local Cleanup by default, or an explicitly configured local `llama-server` loopback endpoint.
- Setup scripts download open local model artifacts and Homebrew packages as needed.

## Troubleshooting

### Automatic paste does not work

1. Open Local Wispr **Settings**.
2. Enable **Paste Helper** Accessibility.
3. Approve **Local Wispr Paste Helper** in System Settings.
4. Click **Refresh** or wait for the settings window to detect the permission.

If it still fails, run:

```sh
scripts/reset-permissions.sh
scripts/install-app.sh
```

### Hotkey is unavailable

The hotkey may need Accessibility permission or may conflict with another app. Approve Accessibility, then choose **Retry Hotkey** from the menu bar item.

### Transcription engine is missing

Run:

```sh
scripts/check-local-engines.sh
```

If `whisper-cli` or the model is missing, run:

```sh
scripts/setup-local-engines.sh
```

### llama.cpp cleanup is unavailable

Local Wispr can still run with the basic cleanup fallback. If you want `llama.cpp` cleanup, install the local engines and check model status:

```sh
scripts/setup-local-engines.sh
scripts/check-local-engines.sh
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/build-app.sh` | Build release app bundles into `dist/` |
| `scripts/install-app.sh` | Install stable app bundles into `~/Applications` and launch Local Wispr |
| `scripts/setup-local-engines.sh` | Install local STT and optional cleanup dependencies |
| `scripts/check-local-engines.sh` | Print local engine availability |
| `scripts/smoke-local-engines.sh` | Run a small local engine smoke test |
| `scripts/start-llama-server.sh` | Start a warmed local `llama.cpp` cleanup server |
| `scripts/benchmark-timings.sh` | Summarize full-pipeline timing logs |
| `scripts/benchmark-rewrite-loop.sh` | Replay synthetic rewrite/cleanup fixtures and emit optimization metrics |
| `scripts/preflight-autoresearch.sh` | Check privacy/artifact/endpoint guardrails before long optimization runs |
| `scripts/with-llama-server.sh` | Run a command under a managed loopback llama-server with benchmark-tunable server params |
| `scripts/check-release-artifacts.sh` | Scan release staging/output paths for benchmark, log, audio, model, or cert artifacts |
| `scripts/reset-permissions.sh` | Reset macOS TCC records for Local Wispr and the paste helper, including Accessibility/PostEvent/ListenEvent |
| `scripts/signing-status.sh` | Show signing identities and current app signatures |

## Status

This is an experimental MVP. The current focus is making the core macOS dictation loop feel reliable before adding richer dictation modes, model management, packaging, or release automation.

# Local Wispr

Local Wispr is a native macOS menu bar app for fast, fully local dictation. Hold a global hotkey, speak naturally, release, and Local Wispr transcribes, lightly rewrites, and inserts polished text into the active app.

The project is currently an early macOS prototype focused on proving the end-to-end local dictation loop: reliable capture, local speech-to-text, local cleanup, safe paste insertion, and smooth macOS permission handling.

## Highlights

- **Local-first pipeline**: microphone audio, transcription, cleanup, and timing logs stay on the machine.
- **Native macOS UX**: menu bar app, no Dock icon, floating status panel, SwiftUI settings.
- **Hold-to-dictate hotkey**: press and hold `Control` + `Option` + `Space`; release to process.
- **Local speech-to-text**: `whisper.cpp` CLI adapter with a default local Whisper model.
- **Local cleanup**: optional Ollama rewrite model with a basic local cleanup fallback.
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

Install `whisper.cpp`, download the default Whisper model, install Ollama, and pull the default cleanup model:

```sh
scripts/setup-local-engines.sh
```

The default engine locations are:

```text
whisper-cli:          /opt/homebrew/bin/whisper-cli or PATH
Whisper model:        ~/Library/Application Support/LocalWispr/Models/whisper/ggml-base.en.bin
Ollama cleanup model: qwen3:0.6b
```

Check engine status:

```sh
scripts/check-local-engines.sh
```

Smoke-test local engine responses:

```sh
scripts/smoke-local-engines.sh
```

Ollama is optional. To install only the speech-to-text path and use the built-in cleanup fallback:

```sh
LOCAL_WISPR_WITH_OLLAMA=0 scripts/setup-local-engines.sh
```

Latency-oriented cleanup knobs:

```sh
# Skip the LLM for short/simple transcripts and use local rules instead. Default: 120 chars.
LOCAL_WISPR_FAST_CLEANUP_MAX_CHARS=120

# Cap LLM cleanup time before falling back to local rules. Default: 650 ms.
LOCAL_WISPR_LLM_CLEANUP_BUDGET_MS=650

# Cap cleanup generation length. Default is dynamic, max 192 tokens.
LOCAL_WISPR_CLEANUP_NUM_PREDICT=128
```

You can also run a warmed `llama.cpp` server instead of Ollama:

```sh
LOCAL_WISPR_REWRITE_ENGINE=llama-server
LOCAL_WISPR_LLAMA_SERVER_URL=http://127.0.0.1:8080/completion
```

After changing engines or environment variables, choose **Reload Engines** from the Local Wispr menu or relaunch the app from the same environment.

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

## Benchmarking

Local Wispr writes one timing line per dictation session to:

```text
~/Library/Logs/LocalWispr/mock-flow.log
```

Summarize the full pipeline:

```sh
scripts/benchmark-timings.sh
```

Limit the summary to the most recent successful sessions:

```sh
scripts/benchmark-timings.sh --last 20
```

Export raw timing rows as CSV:

```sh
scripts/benchmark-timings.sh --csv > timings.csv
```

New timing logs include stage-level fields such as `hotkey_to_recording_ms`, `audio_start_ms`, `audio_stop_ms`, `stt_ms`, `rewrite_ms`, `insert_ms`, `cleanup_engine_used`, and `release_to_output_ms`. The most important user-facing metric is `release_to_output_ms`: time from releasing the hotkey to pasted/copied output.

## Architecture

```text
LocalWispr.app
├─ AppDelegate / menu bar lifecycle
├─ HotkeyController          Carbon global hold hotkey
├─ AudioCapture              AVFoundation microphone capture
├─ DictationSession          recording → STT → cleanup → insertion orchestration
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
- Ollama, when enabled, runs against the local Ollama server at `127.0.0.1:11434`.
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

### Ollama cleanup is unavailable

Local Wispr can still run with the basic cleanup fallback. If you want Ollama cleanup, make sure the service is running and the model is pulled:

```sh
brew services start ollama
ollama pull qwen3:0.6b
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/build-app.sh` | Build release app bundles into `dist/` |
| `scripts/install-app.sh` | Install stable app bundles into `~/Applications` and launch Local Wispr |
| `scripts/setup-local-engines.sh` | Install local STT and optional cleanup dependencies |
| `scripts/check-local-engines.sh` | Print local engine availability |
| `scripts/smoke-local-engines.sh` | Run a small local engine smoke test |
| `scripts/benchmark-timings.sh` | Summarize full-pipeline timing logs |
| `scripts/reset-permissions.sh` | Reset macOS TCC records for Local Wispr and the paste helper, including Accessibility/PostEvent/ListenEvent |
| `scripts/signing-status.sh` | Show signing identities and current app signatures |

## Status

This is an experimental MVP. The current focus is making the core macOS dictation loop feel reliable before adding richer dictation modes, model management, packaging, or release automation.

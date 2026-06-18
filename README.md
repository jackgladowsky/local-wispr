# Local Wispr

Local Wispr is a native macOS menu bar app for fast, fully local dictation. Hold the hotkey, speak, release, and the app transcribes, lightly cleans up, and inserts the text into the active app.

## Features

- Local microphone capture, transcription, cleanup, and timing logs.
- Native menu bar UX with a small status panel and SwiftUI settings.
- Hold-to-dictate hotkey: `Control` + `Option` + `Space`.
- Streaming Moonshine speech-to-text via a local loopback sidecar.
- Basic local cleanup by default, with optional loopback `llama.cpp` server cleanup.
- Clipboard-preserving paste with focus and secure-field checks.
- Separate paste helper app so Accessibility permission survives main-app rebuilds.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools / Swift 6
- Python 3 for the local Moonshine sidecar
- Homebrew for optional `llama.cpp` cleanup setup
- Microphone permission for dictation
- Accessibility permission for automatic paste; without it, output is copied for manual `Command-V`

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

Open Local Wispr from the menu bar, complete permissions in **Settings**, then hold `Control` + `Option` + `Space` to dictate.

## Local Engines

Set up the default local runtime and check it:

```sh
scripts/setup-local-engines.sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
```

Default paths:

```text
Moonshine venv:  ~/Library/Application Support/LocalWispr/Moonshine/venv
Moonshine script: ~/Library/Application Support/LocalWispr/Moonshine/moonshine_server.py
Cleanup model:   ~/Library/Application Support/LocalWispr/Models/cleanup/cleanup.gguf
```

Local Wispr now uses Moonshine for STT. When the Moonshine runtime is installed, the app starts a managed loopback sidecar on `127.0.0.1:8179` and uses the sidecar's streaming-session API by default: it opens a stream on key-down, feeds mic buffers while recording, then finalizes the stream on key-up.

You can also run the sidecar manually:

```sh
scripts/start-moonshine-server.sh
```

The default backend is Moonshine Voice, the optimized ONNX/C++ runtime, using `en/small-streaming`. Useful overrides:

```sh
LOCAL_WISPR_MOONSHINE_VOICE_ARCH=tiny-streaming scripts/start-moonshine-server.sh
LOCAL_WISPR_MOONSHINE_VOICE_ARCH=medium-streaming scripts/start-moonshine-server.sh
LOCAL_WISPR_MOONSHINE_STREAM_UPLOAD_SECONDS=0.05 scripts/install-app.sh
LOCAL_WISPR_MOONSHINE_SERVER_URL=http://127.0.0.1:8179/transcribe scripts/install-app.sh
```

A slower Hugging Face Transformers backend is still available for checkpoint experiments:

```sh
LOCAL_WISPR_MOONSHINE_BACKEND=transformers LOCAL_WISPR_MOONSHINE_MODEL=UsefulSensors/moonshine-streaming-tiny scripts/start-moonshine-server.sh
```

Optional LLM cleanup can use a local `llama.cpp` server:

```sh
scripts/start-llama-server.sh
LOCAL_WISPR_REWRITE_ENGINE=llama-server scripts/install-app.sh
```

If no cleanup server is configured, Local Wispr uses Basic Local Cleanup.

## Speed Defaults

The app defaults to the low-latency path on main:

- native Moonshine streaming STT is enabled by default;
- full-session WAV conversion is deferred unless batch fallback needs it;
- final streaming cleanup is skipped for faster release-to-output;
- a managed loopback Moonshine sidecar is started and used automatically when available;
- paste-helper launch attempts and response polling are optimized.

Useful opt-outs for troubleshooting:

```sh
LOCAL_WISPR_DISABLE_STREAMING=1 scripts/install-app.sh
LOCAL_WISPR_MOONSHINE_STREAMING=0 scripts/install-app.sh
LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP=0 scripts/install-app.sh
LOCAL_WISPR_DISABLE_MANAGED_MOONSHINE_SERVER=1 scripts/install-app.sh
```

Clipboard restore remains on by default. Unsafe insertion experiments are intentionally opt-in via `LOCAL_WISPR_INSERT_UNSAFE_*` variables.

## Permissions

| Permission | Required | Purpose | Fallback |
| --- | --- | --- | --- |
| Microphone | Yes | Captures dictation audio locally | Real dictation is unavailable |
| Main App Accessibility | Optional | Lets the app post paste keystrokes | Copies output to clipboard |
| Paste Helper Accessibility | Optional | Stable automatic paste across rebuilds | Copies output to clipboard |

The recommended development path is to approve **Local Wispr Paste Helper** for Accessibility. If macOS permission state gets stale, reset it with:

```sh
scripts/reset-permissions.sh
```

## Build, Install, and Release

```sh
swift test
scripts/build-app.sh
scripts/install-app.sh
scripts/package-release.sh
```

Release assets are written to `dist/release/` as a DMG, ZIP, and `SHA256SUMS.txt`. See [`docs/release.md`](docs/release.md) for signing, notarization, and GitHub release details.

## Repository Layout

```text
Sources/LocalWisprCore/      app logic
Sources/LocalWispr/          menu bar app entry point
Sources/LocalWisprPasteHelper/ stable paste helper
Packaging/                  app bundle plists
scripts/                    setup, build, install, release, and engine helpers
Tests/                      unit tests
```

## Privacy

Local Wispr is local-first. It does not use cloud transcription, accounts, remote history, or analytics. Audio temp files are written under the system temp directory during a dictation session and removed afterward. STT and cleanup servers are restricted to loopback URLs by default.

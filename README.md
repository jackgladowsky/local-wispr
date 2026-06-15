# Local Wispr

Native macOS MVP for a fully local dictation utility.

## Current Slice

The current slice has the full native flow and engine adapters:

- Menu bar app
- Top-center floating panel
- Control-Option-Space hold hotkey
- Real microphone capture to local audio
- Normalized WAV conversion for STT
- whisper.cpp CLI adapter
- Ollama cleanup adapter
- Basic local cleanup fallback
- Mock flow for testing
- Clipboard-preserving paste path
- Local timing log

## Build

```sh
swift build
```

## Build App Bundle

```sh
scripts/build-app.sh
open "dist/Local Wispr.app"
```

## Stable Install

For one-time macOS permission approval, install the app to a stable location:

```sh
scripts/install-app.sh
```

This installs and launches:

```text
~/Applications/Local Wispr.app
```

Authorize this installed copy in System Settings. Avoid authorizing temporary builds from `dist/`, because rebuilds can make macOS treat them as a changed app.

For the smoothest permission behavior across rebuilds, sign with a stable code signing identity:

```sh
LOCAL_WISPR_CODESIGN_IDENTITY="Apple Development: Your Name (...)" scripts/build-app.sh
scripts/install-app.sh
```

If no signing identity exists, the build script uses an ad-hoc signature. That works for local testing, but macOS may keep the Accessibility checkbox visually enabled while the rebuilt binary no longer matches the old trust record.

Inspect signing state:

```sh
scripts/signing-status.sh
```

Reset stale macOS permission records:

```sh
scripts/reset-permissions.sh
```

The hotkey and paste flow need Accessibility permission. Use the menu bar item's "Prompt for Accessibility" action, then enable Local Wispr in System Settings.

After granting permission, choose "Retry Hotkey" from the menu bar item or relaunch the app.

The real dictation path also needs Microphone permission. Use "Prompt for Microphone" from the menu bar item.

Once Microphone and Accessibility are approved for `~/Applications/Local Wispr.app`, Local Wispr should not ask every time. It will paste into the currently focused cursor using the same path as a normal Command-V paste.

## Local Engine Setup

Install whisper.cpp, download the default local Whisper model, install Ollama, and pull the default cleanup model:

```sh
scripts/setup-local-engines.sh
```

Check engine status:

```sh
scripts/check-local-engines.sh
```

Smoke-test local engine responses:

```sh
scripts/smoke-local-engines.sh
```

The app discovers:

```text
whisper-cli: /opt/homebrew/bin/whisper-cli or PATH
Whisper model: ~/Library/Application Support/LocalWispr/Models/whisper/ggml-base.en.bin
Ollama cleanup model: qwen3:0.6b
```

You can skip Ollama and use the basic local cleanup fallback:

```sh
LOCAL_WISPR_WITH_OLLAMA=0 scripts/setup-local-engines.sh
```

After setup, choose "Reload Engines" from the Local Wispr menu or relaunch the app.

## Debug Log

Mock-flow timing is written to:

```text
~/Library/Logs/LocalWispr/mock-flow.log
```

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
~/Applications/Local Wispr Paste Helper.app
```

Authorize the installed copies in System Settings. Avoid authorizing temporary builds from `dist/`, because rebuilds can make macOS treat them as changed apps.

`Local Wispr Paste Helper.app` is intentionally separate and stable. `scripts/install-app.sh` keeps an existing helper in place by default so Accessibility trust can survive main-app rebuilds. To intentionally replace the helper:

```sh
LOCAL_WISPR_UPDATE_HELPER=1 scripts/install-app.sh
```

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

Microphone permission is required for real dictation. Accessibility is optional but enables automatic paste. Without Accessibility, Local Wispr still copies the cleaned output so you can press Command-V manually.

Use Settings → Microphone to approve audio capture. Use Settings → Main App Accessibility or Settings → Paste Helper to approve auto-paste. The settings window polls macOS after opening System Settings and automatically retries the hotkey when permission flips to allowed.

Once Microphone is approved and either the main app or paste helper has Accessibility, Local Wispr should not ask every time. It will paste into the currently focused cursor using the same path as a normal Command-V paste.

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

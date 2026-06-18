# Troubleshooting

## The app opens, but dictation does not start

1. Open **Local Wispr → Settings** from the menu bar.
2. Confirm Microphone permission is allowed.
3. Re-run engine checks:

```sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
```

If permissions look stale, reset them:

```sh
scripts/reset-permissions.sh
```

## Dictation works, but text is not pasted

Automatic paste requires Accessibility trust. The recommended development path is to approve **Local Wispr Paste Helper** in macOS Settings.

If paste is unavailable, Local Wispr copies the final text to the clipboard so you can press `Command-V` manually.

Reset stale Accessibility state:

```sh
scripts/reset-permissions.sh
```

Then reopen the app and approve the helper again.

## Native Moonshine is not found

Install/check the default native model:

```sh
scripts/setup-moonshine-native.sh
scripts/check-local-engines.sh
```

Use a specific model directory when launching:

```sh
LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR=/path/to/model scripts/install-app.sh
```

## Streaming path seems broken

Temporarily disable streaming to isolate the batch/fallback path:

```sh
LOCAL_WISPR_DISABLE_STREAMING=1 scripts/install-app.sh
```

Or disable only native streaming:

```sh
LOCAL_WISPR_DISABLE_NATIVE_STREAMING_STT=1 scripts/install-app.sh
```

## Cleanup output is too aggressive or too slow

The default cleanup is intentionally basic and local. Optional `llama.cpp` cleanup is available, but it can add latency:

```sh
scripts/start-llama-server.sh
LOCAL_WISPR_REWRITE_ENGINE=llama-server scripts/install-app.sh
```

For the fastest streaming path, keep final streaming cleanup skipped:

```sh
LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP=1 scripts/install-app.sh
```

## Where are logs?

Timing logs default to:

```text
~/Library/Logs/LocalWispr/mock-flow.log
```

Use a custom log for experiments:

```sh
LOCAL_WISPR_TIMING_LOG="$PWD/local-wispr-timing.log" scripts/install-app.sh
```

Useful fields include:

- `hotkey_to_recording_ms`
- `audio_start_ms`
- `stt_ms`
- `rewrite_ms`
- `insert_ms`
- `release_to_output_ms`

## The menu bar app is running but I need to restart it

```sh
pkill -x LocalWispr || true
scripts/install-app.sh
```

The paste helper may keep running; `install-app.sh` intentionally preserves it when possible to avoid unnecessary Accessibility resets.

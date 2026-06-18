# Configuration

Most users should not need environment variables. They are useful for engine experiments, troubleshooting, and release packaging.

Run overrides by prefixing `scripts/install-app.sh`, for example:

```sh
LOCAL_WISPR_DISABLE_STREAMING=1 scripts/install-app.sh
```

## Speech-to-text

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOCAL_WISPR_MOONSHINE_STREAMING` | enabled | Enable native Moonshine streaming STT. |
| `LOCAL_WISPR_DISABLE_STREAMING` | disabled | Disable all streaming paths and use batch behavior. |
| `LOCAL_WISPR_DISABLE_NATIVE_STREAMING_STT` | disabled | Disable native streaming while leaving other streaming code available. |
| `LOCAL_WISPR_DISABLE_MOONSHINE_NATIVE` | disabled | Skip native Moonshine discovery. |
| `LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR` | app support default | Use a specific native model directory. |
| `LOCAL_WISPR_MOONSHINE_VOICE_ARCH` | `medium-streaming` for setup | Model architecture to install with `setup-moonshine-native.sh`. |
| `LOCAL_WISPR_MOONSHINE_STREAM_UPLOAD_SECONDS` | runtime default | Streaming upload cadence for native Moonshine. |
| `LOCAL_WISPR_MOONSHINE_TRAILING_SILENCE_SECONDS` | runtime default | Trailing silence appended before finalizing streaming STT. |
| `LOCAL_WISPR_DISABLE_MANAGED_MOONSHINE_SERVER` | disabled | Disable managed loopback sidecar fallback. |
| `LOCAL_WISPR_SETUP_MOONSHINE_SERVER` | disabled | Install the optional Python Moonshine sidecar. |

## Cleanup

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOCAL_WISPR_REWRITE_ENGINE` | basic local cleanup | Set to `llama-server` to use an optional loopback cleanup server. |
| `LOCAL_WISPR_LLAMA_SERVER_URL` | loopback default | Completion endpoint for optional `llama.cpp` cleanup. |
| `LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP` | enabled | Skip final cleanup on streaming path for lower release-to-output latency. |

## Insertion and paste behavior

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOCAL_WISPR_INSERT_UNSAFE_*` | disabled | Experimental insertion latency toggles. Keep disabled for normal use. |
| `LOCAL_WISPR_UPDATE_HELPER` | disabled | Force paste helper replacement during install. |
| `LOCAL_WISPR_RESET_TCC_ON_HELPER_UPDATE` | enabled | Reset Accessibility records when the helper changes. |
| `LOCAL_WISPR_RESET_ACCESSIBILITY_ON_INSTALL` | disabled | Reset Accessibility records during install. |

## Logging and release packaging

| Variable | Default | Purpose |
| --- | --- | --- |
| `LOCAL_WISPR_TIMING_LOG` | `~/Library/Logs/LocalWispr/mock-flow.log` | Override timing log location. |
| `LOCAL_WISPR_RELEASE_VERSION` | plist version | Version stamped into release artifacts. |
| `LOCAL_WISPR_SKIP_BUILD` | disabled | Reuse existing `dist/` app bundles during packaging. |
| `LOCAL_WISPR_CODESIGN_IDENTITY` | ad-hoc signing | Developer ID identity for local release signing. |

## Recommended troubleshooting profiles

Disable streaming to isolate batch STT:

```sh
LOCAL_WISPR_DISABLE_STREAMING=1 scripts/install-app.sh
```

Use a smaller Moonshine model for setup experiments:

```sh
LOCAL_WISPR_MOONSHINE_VOICE_ARCH=tiny-streaming scripts/setup-moonshine-native.sh
LOCAL_WISPR_MOONSHINE_NATIVE_MODEL_DIR="$HOME/Library/Application Support/LocalWispr/Moonshine/models/en/tiny-streaming" scripts/install-app.sh
```

Enable optional local LLM cleanup:

```sh
scripts/start-llama-server.sh
LOCAL_WISPR_REWRITE_ENGINE=llama-server scripts/install-app.sh
```

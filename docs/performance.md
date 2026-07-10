# Performance and market context

Local Wispr is optimized for **release-to-output latency**: the time from letting go of the hotkey to text appearing in the target app.

It is not trying to be a general transcription suite. The goal is a small macOS dictation loop that feels immediate.

## What is optimized

| Optimization | Why it matters |
| --- | --- |
| Native Moonshine streaming starts on key-down | Speech-to-text work begins while the user is still talking. |
| Mic buffers feed STT directly | Avoids waiting for a full recording file before transcription starts. |
| Full-session WAV conversion is deferred | Batch fallback can still work, but the fast path avoids unnecessary conversion. |
| Final LLM cleanup is skipped by default on streaming | Basic local cleanup avoids adding model latency after release. |
| Smart Cleanup V1 is timeout-budgeted | Optional OpenAI-compatible cleanup can improve text quality without blocking indefinitely. |
| Paste helper is kept stable across rebuilds | Reduces permission churn and keeps insertion fast during development. |
| Clipboard restore is asynchronous | Paste latency is not blocked by clipboard restoration. |
| Timing logs are always written | Regressions can be measured instead of guessed. |

## Timing fields

Timing logs default to:

```text
~/Library/Logs/LocalWispr/mock-flow.log
```

Important fields:

| Field | Meaning |
| --- | --- |
| `hotkey_to_recording_ms` | Time from hotkey press to audio capture start. |
| `audio_start_ms` | Microphone engine startup time. |
| `recording_ms` | Held dictation duration. |
| `stt_ms` | Final STT work after release. |
| `rewrite_ms` | Cleanup/rewrite time. |
| `insert_ms` | Text insertion time. |
| `release_to_output_ms` | End-user latency after key release. |
| `total_session_ms` | Full hotkey-to-output duration. |

For an experiment log in the checkout:

```sh
LOCAL_WISPR_TIMING_LOG="$PWD/local-wispr-timing.log" scripts/install-app.sh
```

Then dictate a few phrases and inspect recent runs:

```sh
tail -n 20 local-wispr-timing.log
```

## Benchmark methodology

A fair dictation benchmark should separate:

1. **hotkey-to-recording** — does capture start immediately?
2. **speech duration** — how long did the user speak?
3. **release-to-output** — how long after release until text appears?
4. **accuracy/readability** — did the output match useful intent?
5. **privacy mode** — local model, cloud model, or hybrid?
6. **paste behavior** — automatic insertion vs copy-to-clipboard.

Avoid comparing only raw transcription speed. For a hold-to-talk app, users mostly feel the delay after they stop talking.

## Smart Cleanup V1

Smart Cleanup V1 keeps local Moonshine STT and sends only the transcript plus optional small context to an OpenAI-compatible chat completions endpoint. It can point at:

- local `llama.cpp` server OpenAI-compatible mode;
- a local gateway such as LM Studio/Ollama if it exposes `/v1/chat/completions`;
- a remote OpenAI-compatible API when explicitly configured with an API key.

The implementation is intentionally latency-safe:

- it is opt-in via `LOCAL_WISPR_REWRITE_ENGINE=smart-hosted` or `openai-compatible`;
- non-loopback endpoints require explicit opt-in and an API key;
- the existing `FallbackRewriteEngine` keeps a hard latency budget through `LOCAL_WISPR_LLM_CLEANUP_BUDGET_MS`;
- failed/slow cleanup falls back to Basic Local Cleanup;
- `LOCAL_WISPR_SMART_CLEANUP_SHORT_CIRCUIT=1` can keep short plain snippets on the fast local cleanup path.

Local OpenAI-compatible llama.cpp example:

```sh
scripts/start-llama-server.sh
LOCAL_WISPR_REWRITE_ENGINE=smart-hosted \
LOCAL_WISPR_SMART_CLEANUP_URL=http://127.0.0.1:8080/v1/chat/completions \
LOCAL_WISPR_SMART_CLEANUP_MODEL=local-cleanup \
LOCAL_WISPR_LLM_CLEANUP_BUDGET_MS=650 \
  scripts/install-app.sh
```

For hosted APIs, start with a small/fast model and a tight timeout. The quality win comes from better cleanup, but every remote call competes directly with release-to-output latency.

## Market context

Paid dictation/transcription apps generally optimize for different tradeoffs:

| Product | Public positioning | Pricing signal |
| --- | --- | --- |
| Wispr Flow | Cross-platform AI dictation and rewrite, cloud service by default | Pro pricing is advertised at $15/user/month or $12/user/month annually on Wispr Flow's pricing page. |
| Superwhisper | On-device dictation for Mac/iOS/Windows with power-user workflows | Public docs advertise a free tier and paid Pro/lifetime options. |
| MacWhisper | Local audio/video file transcription app for Mac | Primarily file-first transcription with free/pro app distribution. |

Local Wispr's positioning is narrower and more developer-centric:

- no subscription or account in the current local app;
- default no-cloud STT path;
- straightforward Swift implementation instead of a closed product surface;
- optimized for short, frequent, system-wide dictation snippets;
- explicit timing logs so speed claims can be tested locally.

Prices and product features change often. Before publishing marketing copy, verify current vendor pages directly.

## References for market checks

- Wispr Flow pricing: <https://wisprflow.ai/pricing>
- Superwhisper Pro docs: <https://superwhisper.com/docs/get-started/sw-pro>
- Superwhisper Mac app page: <https://superwhisper.com/voice-to-text-mac>
- MacWhisper: <https://macwhisper.org/>

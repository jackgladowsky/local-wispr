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

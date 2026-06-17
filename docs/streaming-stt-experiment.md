# Streaming STT experiment

Local Wispr's default dictation path remains batch-oriented: record the full hotkey session, convert to Whisper-ready WAV, transcribe, clean up, then insert.

An off-by-default experimental path can reduce post-release STT latency by doing chunk transcription while the hotkey is still held.

## Enable

```sh
LOCAL_WISPR_EXPERIMENTAL_STREAMING=1 scripts/install-app.sh
```

Fastest experimental mode skips the release-time final cleanup/cohesion pass and inserts the assembled speculative draft:

```sh
LOCAL_WISPR_EXPERIMENTAL_STREAMING=1 \
LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP=1 \
  scripts/install-app.sh
```

## Knobs

```sh
LOCAL_WISPR_STREAMING_CHUNK_SECONDS=2.5
LOCAL_WISPR_STREAMING_MIN_CHUNK_SECONDS=0.25
LOCAL_WISPR_STREAMING_CHUNK_GRACE_SECONDS=2.0
```

## How it works

- `AudioCapture` keeps the normal full-session recording for fallback.
- When streaming is enabled, it also rotates microphone buffers into local temporary CAF chunks.
- Finalized chunks are converted to 16 kHz mono WAV and passed to `SpeculativeDictationCoordinator`.
- The coordinator runs the configured `STTEngine` and `RewriteEngine` on each chunk while recording continues.
- On release, `DictationSession` waits briefly for expected chunks, assembles chunk text in order, and either runs final cleanup or skips it when `LOCAL_WISPR_STREAMING_SKIP_FINAL_CLEANUP=1`.
- If chunking/STT/cleanup fails or a chunk is missed, the app falls back to the normal full-recording batch path.

## Current evidence

From local timing notes in `~/Library/Logs/LocalWispr/mock-flow.log`:

| Mode | n | Avg release-to-output | Median | P90 | Avg STT | Avg rewrite |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Main `real` | 10 | 488.5 ms | 375.2 ms | 796.5 ms | 238.7 ms | 89.4 ms |
| Experimental streaming | 10 | 519.8 ms | 363.6 ms | 1009.9 ms | 191.1 ms | 166.2 ms |

No-final-cleanup experimental rows:

| Window | Avg release-to-output | Avg STT | Avg rewrite | Avg insert |
| --- | ---: | ---: | ---: | ---: |
| Latest 5 rows | 345.4 ms | 187.1 ms | 0.5 ms | 107.1 ms |

Interpretation: streaming improved the STT stage, but the final cleanup/cohesion pass can erase the user-facing win. The no-final-cleanup path is fastest, but it needs broader accuracy checks before it should become default.

## Guardrails

- Default app behavior is unchanged unless `LOCAL_WISPR_EXPERIMENTAL_STREAMING=1` is set.
- Temporary audio files are local and removed after processing, cancellation, or conversion failure.
- Do not commit real or personal audio clips.
- Validate with `swift test`, `git diff --check`, and focused manual timing runs with `LOCAL_WISPR_TIMING_LOG=/path/to/run.log`.

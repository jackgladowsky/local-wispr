# Local Wispr MVP Spec

Version: 0.1
Date: 2026-06-14

## Product Goal

Build a fully local macOS dictation utility that feels native on a MacBook: press a hotkey, speak naturally, release, and get polished text inserted into the active app with very low latency.

The MVP should prove four things:

- Speech is captured instantly and reliably from a global hotkey.
- Transcription and cleanup happen locally with warm models.
- The output is clean enough to use without editing most of the time.
- The app pastes safely into real macOS apps without breaking the user's clipboard or focus.

## Non-Goals For MVP

- No cloud transcription or cleanup.
- No iOS app.
- No team sync, account system, analytics, or remote history.
- No always-listening ambient mode.
- No App Store release requirement in the first build.
- No complex command agent behavior beyond simple rewrite styles.

## Recommended MVP Direction

Build a native Swift macOS menu bar app using SwiftUI for settings and AppKit for the floating panel and system integration.

Recommended default stack:

```text
App shell:        SwiftUI + AppKit
Audio capture:    AVAudioEngine
Hotkey/input:     Carbon hotkey and/or event tap, wrapped behind HotkeyController
Floating UI:      borderless NSPanel near top center of active display
STT engine:       WhisperKit/Core ML first, benchmarked against whisper.cpp Metal
Cleanup engine:   embedded local rewrite model via llama.cpp or MLX
Dev adapter:      Ollama allowed only as a benchmark/prototype adapter
Insertion:        clipboard-preserving paste with Accessibility permission
```

Why this path:

- Swift/AppKit gives the best chance of a polished, low-friction Mac utility.
- WhisperKit is the cleanest native Apple Silicon STT starting point.
- whisper.cpp with Metal should stay as the fallback if it benchmarks faster or more stable.
- Ollama is convenient for testing, but it should not be the production dependency because it adds setup friction and less predictable startup behavior.
- The cleanup model should stay warm in memory and run with a tight token budget.

## First Build Slice

The first build should prove the app loop before real models are integrated.

Locked decisions for the first implementation:

- Native Swift macOS app.
- Menu bar utility with no Dock icon by default.
- Hold-to-record interaction.
- Top-center AppKit floating panel.
- Mock STT and mock cleanup engines first.
- Clipboard-preserving paste before direct Accessibility text insertion.
- No partial insertion.
- No rolling STT until the basic flow is reliable and measured.

First user-testable slice:

1. User presses the global hotkey.
2. Panel appears in listening state.
3. User releases the hotkey.
4. Mock engine returns deterministic cleaned text.
5. App pastes into the active field.
6. Clipboard is restored safely.
7. Timing metrics are written to a local debug log.

This slice is intentionally small. If this does not feel smooth with mocks, real models will only make it harder to diagnose.

## Core User Flow

Primary flow:

1. User presses and holds the global dictation hotkey.
2. The top-center floating panel appears within 80ms and shows listening state.
3. App captures microphone audio immediately.
4. User releases the hotkey.
5. App trims silence, finalizes transcription, rewrites the transcript locally, and inserts cleaned text.
6. Panel confirms insertion and fades away.

Cancel flow:

1. User presses Escape while recording or processing.
2. App stops audio capture, drops the transcript, restores any temporary clipboard state, and does not paste.

Fallback flow:

1. If the app cannot safely paste, it copies cleaned text to the clipboard.
2. Panel shows a concise "Copied" state.
3. The user's previous clipboard is restored only when doing so will not destroy the new intentional copied output.

## Native macOS UX Requirements

The UI should feel like a quiet Apple utility, not a web app.

- Menu bar app by default, no Dock icon in normal operation.
- Small top-center floating panel using AppKit, not a private notch API.
- Panel uses native materials, soft shadows, SF Symbols, and restrained animation.
- States are visible at a glance: idle, listening, transcribing, polishing, inserted, copied, error.
- Settings live in a compact SwiftUI window.
- No marketing screen, oversized hero UI, or card-heavy onboarding.
- Onboarding only appears when permissions or model setup are needed.
- UI text must stay short and functional.

Default controls:

- Hold hotkey: configurable, default candidate `Control+Option+Space`.
- Toggle recording: optional secondary mode, disabled by default.
- Cancel: `Escape`.
- Retry last insertion: menu item and optional keyboard shortcut.
- Literal mode: temporary modifier or menu setting that prevents cleanup beyond punctuation.

## Permission And Onboarding Requirements

The app must handle permissions as product states, not surprise failures.

Required permissions:

- Microphone: for audio capture.
- Accessibility: for posting paste keystrokes and interacting with the active app.

Optional permissions:

- Input monitoring: only if the chosen hotkey/event-tap path requires it.

Onboarding acceptance criteria:

- First launch detects missing permissions before recording.
- Each permission has a single native-looking explanation and a button to open the right System Settings pane.
- The app can recover after the user grants permission without requiring a restart when possible.
- If Accessibility is denied, the app can still copy cleaned output to the clipboard.

## System Architecture

```text
HotkeyController
  -> DictationSession
      -> AudioCapture
      -> EndpointDetector
      -> STTEngine
      -> RewriteEngine
      -> InsertionController
      -> PanelStateStore
```

### Main Components

`HotkeyController`

- Registers global hold and release events.
- Emits `recordStart`, `recordStop`, and `cancel`.
- Isolates Carbon/event-tap details from the rest of the app.

`DictationSession`

- Owns one dictation lifecycle from hotkey down to inserted/copied/error.
- Captures target app and focused element at start.
- Coordinates audio, STT, cleanup, insertion, timing, and UI state.

`AudioCapture`

- Uses `AVAudioEngine`.
- Records mono PCM at a model-friendly sample rate.
- Writes into an in-memory ring buffer.
- Can optionally save debug WAV files in developer mode.

`EndpointDetector`

- Trims leading and trailing silence.
- Uses hotkey release as the primary endpoint for MVP.
- Uses VAD only to trim silence and reduce wasted STT work.
- Does not auto-submit speech in MVP unless toggle mode is enabled.

`STTEngine`

- Provides a stable protocol so WhisperKit and whisper.cpp can be benchmarked.
- Loads model at app startup or first permission-complete idle.
- Keeps model warm after first use.
- Returns transcript text plus segment timestamps when available.

`RewriteEngine`

- Provides a stable protocol for local cleanup models.
- Keeps the model warm in memory.
- Runs at low temperature with strict max output tokens.
- Times out quickly and falls back to raw transcript when cleanup is too slow.

`InsertionController`

- Preserves rich clipboard contents before paste.
- Writes cleaned text to pasteboard.
- Posts Command-V through Accessibility.
- Restores the previous clipboard after paste when safe.
- Falls back to "copy only" if focus changed or paste is blocked.

`PanelStateStore`

- Keeps UI state separate from dictation logic.
- Exposes short status, elapsed time, and errors.

## Data Flow

```text
hotkey down
  -> capture focused app and element
  -> show listening panel
  -> start audio

hotkey up
  -> stop audio
  -> trim silence
  -> transcribe
  -> rewrite
  -> verify focus/paste safety
  -> paste or copy
  -> restore clipboard if safe
  -> hide panel
```

## Streaming And JIT Strategy

MVP should be reliable before it gets clever.

Initial MVP:

- Do not insert partial text.
- Use release-to-submit as the source of truth.
- Start STT only after recording ends unless benchmarks show this misses latency targets.
- Keep STT and rewrite models warm.

Optimized MVP extension:

- While the user is speaking, run STT on rolling chunks in the background.
- Use 1-2 seconds of overlap between chunks.
- Track segment timestamps and only commit text after it is stable across passes.
- Finalize only the remaining audio tail after hotkey release.
- Send one final transcript to cleanup.

Partial transcript rules:

- Never paste partial text.
- Never show unstable words as final.
- Deduplicate overlapping segments by timestamp first, then normalized text similarity.
- If timestamps are missing or unreliable, disable streaming for that engine.

## Cleanup Behavior

The cleanup model is a rewrite engine, not a chat assistant.

Default cleanup prompt:

```text
You are a local dictation cleanup engine.

Rewrite the transcript into clean, natural text.

Rules:
- Preserve the user's meaning.
- Do not add facts, names, dates, links, or commitments.
- Fix punctuation and capitalization.
- Remove filler words when they do not matter.
- Keep names, emails, URLs, code, numbers, and product names as close to the transcript as possible.
- If a word is uncertain, prefer the transcript instead of inventing.
- Preserve profanity and sensitive wording when the user said it.
- Preserve line breaks and list structure when clearly dictated.
- Do not explain your changes.
- Return only the cleaned text.

Transcript:
<<<
{transcript}
>>>
```

Literal mode prompt:

```text
Fix only punctuation, capitalization, and obvious spacing.
Do not rewrite wording.
Return only the corrected text.

Transcript:
<<<
{transcript}
>>>
```

Cleanup settings:

- Temperature: `0.0-0.2`
- Max output: `min(512 tokens, 2x transcript token estimate + 64)`
- Timeout target: `800ms`
- Timeout fallback: paste raw transcript with punctuation cleanup if available

## Model Selection

### STT Candidates

Primary candidate:

- WhisperKit/Core ML with a small or base English model for native Apple Silicon performance.

Fallback candidate:

- whisper.cpp with Metal acceleration if it wins latency, stability, memory, or packaging tests.

Evaluation criteria:

- Warm transcription latency.
- Accuracy on short dictation.
- Behavior on names, punctuation, and filler words.
- Model load time.
- Memory use.
- Ease of packaging in a signed macOS app.
- Availability of timestamps for rolling chunk deduplication.

### Cleanup Candidates

Primary candidates to benchmark:

- Qwen3 small instruct model, quantized, with thinking disabled if applicable.
- Llama 3.2 1B or 3B Instruct, quantized.
- Gemma small instruct model, quantized.

Runtime recommendation:

- Product path: embedded llama.cpp or MLX runtime.
- Prototype-only path: Ollama adapter for quick comparison.

Evaluation criteria:

- p50 and p95 rewrite latency.
- Quality on filler removal and punctuation.
- Conservatism with names, URLs, code, numbers, and commands.
- Memory footprint while warm.
- Behavior with temperature near zero.
- No extra commentary or markdown unless dictated.

## Paste And Clipboard Safety

Insertion must be boringly reliable.

Required behavior:

- Capture frontmost app PID and focused accessibility element at recording start.
- Before paste, verify the target is still compatible.
- Preserve all pasteboard item types, not only plain text.
- Restore the previous clipboard after paste if the current pasteboard still contains the app's temporary text.
- If focus changed, secure input is active, or paste fails, copy cleaned text and show "Copied".
- Never paste into password fields or secure text fields.
- Never paste after cancel.

Test apps:

- TextEdit
- Notes
- Messages
- Slack or Discord
- Chrome/Safari text field
- VS Code or Cursor editor
- Terminal prompt, copy-only acceptable if paste behavior is risky

## Privacy And Local-Only Guarantees

MVP privacy contract:

- No audio, transcript, or rewritten text leaves the Mac.
- The app works offline after models are installed.
- Debug audio/transcript logging is off by default.
- Local history is off by default.
- If history is later added, it must be opt-in, local, searchable, and deletable.
- Model downloads, if needed, are explicit user actions.

Developer mode may log:

- Timing metrics.
- Engine names and model sizes.
- Transcript length.
- Error categories.

Developer mode must not log:

- Audio contents.
- Full transcripts.
- Clipboard contents.

## Performance Targets

Baseline hardware for MVP benchmarks:

- Minimum: Apple Silicon MacBook with 8GB RAM.
- Target: Apple Silicon MacBook with 16GB RAM.

Warm path targets for utterances up to 15 seconds:

```text
hotkey down -> audio capture:      <= 50ms
hotkey down -> visible UI:         <= 80ms
release -> STT final:              p50 <= 600ms, p95 <= 1200ms
STT final -> cleanup final:        p50 <= 400ms, p95 <= 800ms
cleanup final -> paste/copy:       <= 100ms
release -> inserted/copied total:  p50 <= 900ms, p95 <= 1800ms
```

Cold path targets:

```text
app launch -> usable idle:         <= 5s with deferred model warmup
first model warmup complete:       <= 20s on target hardware
first dictation after warmup:      must meet warm path targets
```

Memory targets:

```text
idle app without warm models:      <= 150MB
warm STT + rewrite models:         target <= 3GB, hard ceiling <= 5GB
```

If these targets are not met, priority order is:

1. Keep UI and capture responsiveness instant.
2. Use a smaller cleanup model.
3. Use a smaller STT model.
4. Add rolling STT only after end-to-end reliability is solid.

## Quality Targets

Create a local benchmark set with at least 40 utterances:

- Short command-like dictation.
- Long paragraph dictation.
- Email style.
- Slack style.
- Filler-heavy speech.
- Names and calendar language.
- URLs and email addresses.
- Code identifiers.
- Numbers, prices, and dates.
- Profanity and sensitive wording.
- Ambiguous words where the model should not invent.

Acceptance criteria:

- At least 90 percent of benchmark outputs are usable without editing.
- Zero added facts across the benchmark set.
- Zero dropped URLs, emails, or numeric values.
- No extra assistant commentary.
- No duplicate phrases caused by chunk overlap.
- Literal mode changes wording in 0 benchmark cases.

## Error Handling

The app should degrade gracefully.

Expected errors:

- Microphone permission denied.
- Accessibility permission denied.
- Model missing.
- Model load failed.
- No speech detected.
- STT timeout.
- Cleanup timeout.
- Paste blocked.
- Focus changed.
- Secure field detected.

Fallback behavior:

- Permission denied: show permission-specific panel state and menu action.
- Model missing: open model setup screen.
- No speech: show brief "No speech detected" state, do not paste.
- STT timeout: copy raw partial transcript only if confidence is acceptable.
- Cleanup timeout: paste raw transcript or minimally punctuated transcript.
- Paste blocked: copy cleaned text.
- Focus changed: copy cleaned text instead of pasting.

## Test Plan

Unit tests:

- Hotkey state machine.
- Dictation session state transitions.
- Endpoint trimming.
- Clipboard preservation and restoration logic.
- Focus-change safety logic.
- Cleanup prompt construction.
- Literal mode prompt construction.
- Chunk deduplication logic.

Integration tests:

- Mock STT and rewrite engines for deterministic end-to-end flow.
- Real audio fixture through STT engine.
- Real transcript fixture through rewrite engine.
- Clipboard paste into local test text field.
- Permission-denied simulations where possible.

Manual acceptance tests:

- Fresh install permission flow.
- Record/cancel does not paste.
- Record/release pastes in TextEdit.
- Record/release pastes in browser text area.
- Focus switch during processing results in copy-only.
- Clipboard with rich content is restored after paste.
- Offline mode works after model install.
- App remains responsive during model warmup.

Benchmark command:

```text
local-wispr-bench --suite fixtures/dictation --engine whisperkit --rewrite qwen-small
```

Benchmark output should include:

- Audio duration.
- STT duration.
- Cleanup duration.
- Paste/copy duration.
- Total release-to-output duration.
- Peak memory.
- Output quality label.

## MVP Milestones

### Milestone 1: Test Harness

- Define `STTEngine`, `RewriteEngine`, and `InsertionController` protocols.
- Build mock engines.
- Build fixture-based benchmark runner.
- Add first 40 utterance benchmark suite.

Done when:

- End-to-end dictation flow can be tested without microphone access.
- Benchmark runner produces timing and quality reports.

### Milestone 2: Native Shell

- Create menu bar app.
- Add settings window.
- Add top-center floating panel.
- Add permission onboarding.
- Add configurable hotkey.

Done when:

- User can start/cancel a mock dictation from the global hotkey.
- UI state transitions are smooth and fast.

### Milestone 3: Real Capture And Paste

- Add AVAudioEngine capture.
- Add silence trimming.
- Add clipboard-preserving paste.
- Add focus safety checks.

Done when:

- Spoken audio can be recorded and mock-cleaned text can be pasted into test apps.
- Clipboard restoration passes rich-content tests.

### Milestone 4: Local STT

- Integrate WhisperKit.
- Add warm model loading.
- Add STT benchmark fixtures.
- Compare against whisper.cpp if latency or packaging is weak.

Done when:

- Real recorded utterances produce transcripts locally.
- STT meets warm latency targets on target hardware.

### Milestone 5: Local Cleanup

- Add local rewrite engine.
- Benchmark Qwen/Llama/Gemma candidates.
- Add timeout fallback to raw transcript.
- Add literal mode.

Done when:

- Cleaned output meets quality targets.
- Rewrite latency meets warm targets.

### Milestone 6: Smooth MVP

- Tune panel animation and status timing.
- Add retry/copy menu actions.
- Add debug timing overlay or log export.
- Run full manual acceptance test matrix.

Done when:

- The app feels instant to start, predictable to finish, and safe when something goes wrong.

## Open Decisions

These should be resolved by benchmark, not taste:

- WhisperKit vs whisper.cpp for the default STT engine.
- llama.cpp vs MLX for the embedded cleanup runtime.
- Best default cleanup model under 3GB warm memory.
- Whether rolling STT is needed for MVP latency targets.
- Whether default hotkey should be hold-only or hold/toggle hybrid.
- Whether first distributable build bundles models or uses explicit first-run download.

## Current Sources To Recheck During Implementation

- WhisperKit / Argmax OSS: https://github.com/argmaxinc/argmax-oss-swift
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- llama.cpp server/runtime: https://github.com/ggml-org/llama.cpp
- Ollama API, prototype adapter only: https://docs.ollama.com/api
- Apple macOS app sandboxing: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines

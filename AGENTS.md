# Local Wispr Agent Guide

## Project intent

Local Wispr is a local-first macOS dictation app. Preserve the product promise: private local capture/transcription/cleanup, low-latency hold-to-dictate UX, stable permissions, and easy install/release packaging.

Treat these areas as product-critical:

- microphone capture and temporary audio cleanup;
- Accessibility / paste-helper behavior;
- local engine setup, discovery, and loopback-only networking;
- app bundle, install, and release packaging;
- timing logs and latency-sensitive paths.

## Current architecture defaults

- STT is **Moonshine via a local loopback sidecar**.
  - The app can start a managed sidecar using the local Moonshine Python venv.
  - Native Moonshine streaming is the default fast path.
  - Batch Moonshine is the fallback when streaming cannot finish.
- Whisper is deprecated. Do not reintroduce Whisper CLI/server paths unless Jack explicitly asks.
- Cleanup is Basic Local Cleanup by default, with optional loopback `llama.cpp` server cleanup.
- STT and cleanup server endpoints must remain loopback-only by default. Non-loopback requires an explicit, reviewed opt-in.
- Release app bundles must include the Moonshine sidecar resource when needed.

Useful engine commands:

```sh
scripts/setup-local-engines.sh
scripts/setup-moonshine-server.sh
scripts/start-moonshine-server.sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
scripts/start-llama-server.sh
```

## Branch and worktree policy

- `main` is release-oriented: production app code, tests, install/build/release scripts, and public docs.
- Keep benchmark/autoresearch tooling on the `benchmarking` branch unless Jack explicitly promotes it.
- Experimental performance work belongs on explicit experiment branches/worktrees until approved for merge.
- Follow `~/dev/AGENTS.md` worktree hygiene: do not create visible sibling worktrees under `~/dev`; use `~/dev/.worktrees/<repo>/<slug>/`.
- Do not commit personal audio clips, raw recordings, secrets, certificates, API keys, notary credentials, downloaded model weights, generated release archives, or transient benchmark output.

## Implementation guardrails

- Prefer minimal, reviewable changes that keep the default app path stable.
- Keep privacy defaults strict: audio temp files should be removed after use; raw archive behavior must be opt-in and ignored.
- If changing STT/cleanup behavior, update all relevant surfaces together:
  - engine registry/discovery;
  - app startup/controller lifecycle;
  - setup/check/smoke/start scripts;
  - README/settings text;
  - focused unit tests.
- If changing permission or paste behavior, test both trusted and fallback copy-to-clipboard paths when possible.
- If changing release packaging, ensure the built `.app` contents and release artifact scanner still match the intended product surface.
- Do not move benchmark harnesses, reusable audio fixtures, or raw audio archive tooling onto `main` without Jack's explicit approval.

## Validation expectations

For code changes, run and report:

```sh
swift test
git diff --check
```

For app/release changes, also run when relevant:

```sh
scripts/build-app.sh
scripts/package-release.sh
```

For local engine/setup changes, also run when relevant:

```sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
```

If a check cannot be run, state why and name the next-best validation.

## Documentation memory

Maintain durable internal notes in Jack's Obsidian vault under `Projects/Local Wispr/` when architecture, release, benchmark, or product decisions change.

Good targets:

- `Projects/Local Wispr/Local Wispr.md` for project status and active workstreams.
- `Projects/Local Wispr/Architecture Decisions.md` for ADR-style decisions and rationale.

Summaries should include date, branch/worktree, decision, evidence/metrics, validation commands, and next steps.

## Privacy and benchmark audio

- Raw `.wav` / `.caf` recording archives are sensitive and should stay opt-in and experimental unless promoted by Jack.
- If audio archiving is enabled for benchmarks, write files under an ignored local/log directory and include paths in timing logs for traceability.
- Never add recorded clips to git unless Jack explicitly asks and the clips are non-sensitive fixtures.

## Release hygiene

- Keep `dist/`, `.build/`, `.auto/`, logs, generated audio, model files, and cert artifacts out of git.
- Release packaging should include only the intended apps/resources and exclude benchmark/audio/model/cert artifacts.
- Run `scripts/check-release-artifacts.sh` directly if release-surface risk is part of the change.

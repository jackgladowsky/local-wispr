# Development

Local Wispr is a Swift Package Manager macOS app with a separate paste helper executable.

## Prerequisites

- macOS 14+
- Xcode Command Line Tools
- Swift 6
- Homebrew for optional `llama.cpp` setup
- Python 3 only for the optional Moonshine sidecar fallback

## Common commands

```sh
swift test
scripts/setup-local-engines.sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
scripts/build-app.sh
scripts/install-app.sh
```

For code changes, run:

```sh
swift test
git diff --check
```

For app/release-surface changes, also run:

```sh
scripts/build-app.sh
scripts/package-release.sh
```

## Local install behavior

`scripts/install-app.sh` builds if needed, installs to `~/Applications`, keeps an existing paste helper when possible to preserve Accessibility trust, then launches the app with any `LOCAL_WISPR_*` environment variables inherited from the shell.

Installed apps:

```text
~/Applications/Local Wispr.app
~/Applications/Local Wispr Paste Helper.app
```

## Repository hygiene

Generated or sensitive files should stay out of git:

- `.build/`, `dist/`, `.swiftpm/`
- raw audio (`*.wav`, `*.caf`, `*.aiff`, etc.)
- local model files (`*.gguf`, `*.bin`, downloaded Moonshine model folders)
- certificates, keys, notarization credentials, and release archives
- transient benchmark output and logs

## Adding engine behavior

If STT or cleanup behavior changes, update the relevant surfaces together:

- engine registry/discovery;
- app startup/session lifecycle;
- setup/check/smoke/start scripts;
- README and docs;
- focused tests.

Keep new network services loopback-only by default.

## Adding UI behavior

The dictation overlay lives in `Sources/LocalWisprCore/Panel/`. Keep it small, fast, and non-distracting:

- no visible text in the listening overlay;
- preserve Accessibility labels from `PanelSnapshot`;
- avoid expensive work in animation views;
- use live mic levels only as normalized values, not raw audio.

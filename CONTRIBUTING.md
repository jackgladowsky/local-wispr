# Contributing

Thanks for your interest in Local Wispr.

This repo is early and product-driven, so contributions should keep the core promise intact: fast, private, local-first macOS dictation.

## Before opening a PR

Run:

```sh
swift test
git diff --check
```

For app packaging, release, or permission changes, also run when relevant:

```sh
scripts/build-app.sh
scripts/package-release.sh
scripts/check-release-artifacts.sh
```

For engine/setup changes, also run when relevant:

```sh
scripts/check-local-engines.sh
scripts/smoke-local-engines.sh
```

## Contribution guidelines

- Keep defaults private and local-first.
- Keep network services loopback-only unless there is an explicit reviewed opt-in.
- Do not commit audio recordings, model weights, logs, certificates, API keys, release archives, or benchmark scratch output.
- Prefer small, reviewable changes with focused tests.
- Update docs when changing setup, engines, permissions, packaging, or user-visible behavior.
- Do not reintroduce Whisper CLI/server paths unless the project explicitly chooses that direction again.

## Good first areas

- Better settings explanations.
- Permission recovery UX.
- Focused tests around insertion and engine fallback behavior.
- Latency log parsing and local benchmark reporting.
- Documentation improvements from a fresh install.

## Reporting bugs

Include:

- macOS version and hardware;
- install path (`~/Applications` or custom);
- whether Microphone and Accessibility permissions are approved;
- relevant `LOCAL_WISPR_*` environment variables;
- the last few timing log lines from `~/Library/Logs/LocalWispr/mock-flow.log` if safe to share.

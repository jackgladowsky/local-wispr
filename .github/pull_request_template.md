## Summary

- 

## Validation

- [ ] `swift test`
- [ ] `git diff --check`
- [ ] `scripts/build-app.sh` if app/package behavior changed
- [ ] `scripts/package-release.sh` if release artifacts changed
- [ ] `scripts/check-local-engines.sh` / `scripts/smoke-local-engines.sh` if engine setup changed

## Privacy / release surface

- [ ] No audio recordings, model weights, logs, certificates, secrets, or release archives were added.
- [ ] New network behavior, if any, is loopback-only by default.
- [ ] User-facing setup or behavior changes are documented.

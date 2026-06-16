# Release workflow

Local Wispr releases are built on GitHub Actions as macOS app bundles packaged into a DMG and ZIP. The workflow is intentionally guarded so an accidental tag does not silently publish an unsigned or unnotarized app.

## What the release workflow does

`.github/workflows/release.yml` runs on:

- `v*` tag pushes
- GitHub Release publication
- manual `workflow_dispatch`

For each release it:

1. resolves the release version from the tag, such as `v0.1.0` -> `0.1.0`
2. runs `swift test`
3. builds both app bundles with `scripts/build-app.sh`
4. stamps `CFBundleShortVersionString` and `CFBundleVersion` into the built app bundles
5. creates:
   - `LocalWispr-VERSION-macOS.dmg`
   - `LocalWispr-VERSION-macOS.zip`
   - `SHA256SUMS.txt`
6. notarizes/staples the DMG when Apple credentials are configured
7. uploads the assets to the GitHub Release

## Required GitHub protection

Create a GitHub Environment named `release` and enable required reviewers for it. The workflow job uses this environment, which gives a human approval gate before release packaging/publishing can proceed.

Recommended environment settings:

- Required reviewers: enabled
- Deployment branches/tags: restrict to protected tags matching `v*` if available in your plan
- Store signing/notary secrets in the `release` environment, not as broad repository secrets

## Required secrets for proper public releases

Add these secrets to the protected `release` environment:

| Secret | Purpose |
| --- | --- |
| `LOCAL_WISPR_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` Developer ID Application certificate |
| `LOCAL_WISPR_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12` certificate |
| `LOCAL_WISPR_CODESIGN_IDENTITY` | Optional explicit identity, e.g. `Developer ID Application: ...` |
| `LOCAL_WISPR_NOTARY_APPLE_ID` | Apple ID email for notarytool |
| `LOCAL_WISPR_NOTARY_PASSWORD` | App-specific password for the Apple ID |
| `LOCAL_WISPR_NOTARY_TEAM_ID` | Apple Developer Team ID |

The workflow refuses to publish a normal release without Developer ID signing and notarization credentials. Manual workflow dispatch has an emergency `allow_unnotarized_release` option, but it should not be used for normal public releases.

## Tag format

Release tags must match:

```text
vMAJOR.MINOR.PATCH
```

Examples:

```text
v0.1.0
v0.2.3
v1.0.0-beta.1
```

## Local packaging dry run

From a macOS checkout:

```sh
scripts/package-release.sh
```

Override the packaged version without editing source plists:

```sh
LOCAL_WISPR_RELEASE_VERSION=0.1.0 scripts/package-release.sh
```

Assets are written to:

```text
dist/release/
```

## Manual notarization dry run

After importing a Developer ID cert locally and exporting notary credentials:

```sh
LOCAL_WISPR_CODESIGN_IDENTITY="Developer ID Application: Your Name (...)" scripts/package-release.sh

LOCAL_WISPR_NOTARY_APPLE_ID="you@example.com" \
LOCAL_WISPR_NOTARY_PASSWORD="app-specific-password" \
LOCAL_WISPR_NOTARY_TEAM_ID="TEAMID" \
  scripts/notarize-release.sh dist/release/*.dmg
```

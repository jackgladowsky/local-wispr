#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/notarize-release.sh PATH_TO_DMG [PATH_TO_DMG...]

Requires:
  LOCAL_WISPR_NOTARY_APPLE_ID          Apple ID email
  LOCAL_WISPR_NOTARY_PASSWORD          app-specific password
  LOCAL_WISPR_NOTARY_TEAM_ID           Apple Developer Team ID

Submits each DMG to Apple's notary service and staples the ticket.
EOF
}

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 64
fi

: "${LOCAL_WISPR_NOTARY_APPLE_ID:?missing LOCAL_WISPR_NOTARY_APPLE_ID}"
: "${LOCAL_WISPR_NOTARY_PASSWORD:?missing LOCAL_WISPR_NOTARY_PASSWORD}"
: "${LOCAL_WISPR_NOTARY_TEAM_ID:?missing LOCAL_WISPR_NOTARY_TEAM_ID}"

for dmg in "$@"; do
    if [[ ! -f "$dmg" ]]; then
        echo "DMG not found: $dmg" >&2
        exit 1
    fi

    echo "Submitting $(basename "$dmg") for notarization..." >&2
    xcrun notarytool submit "$dmg" \
        --apple-id "$LOCAL_WISPR_NOTARY_APPLE_ID" \
        --password "$LOCAL_WISPR_NOTARY_PASSWORD" \
        --team-id "$LOCAL_WISPR_NOTARY_TEAM_ID" \
        --wait

    echo "Stapling notarization ticket to $(basename "$dmg")..." >&2
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
done

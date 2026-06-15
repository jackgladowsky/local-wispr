#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.local-wispr.LocalWispr"
APP="$HOME/Applications/Local Wispr.app"

if pgrep -x LocalWispr >/dev/null 2>&1; then
    pkill -x LocalWispr || true
    sleep 0.5
fi

tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 || true

defaults delete "$BUNDLE_ID" permissions.completedSetup >/dev/null 2>&1 || true
defaults delete "$BUNDLE_ID" permissions.completedSetupDate >/dev/null 2>&1 || true

if [[ -d "$APP" ]]; then
    open -n "$APP"
fi

echo "Reset Accessibility/Microphone permission records for $BUNDLE_ID"

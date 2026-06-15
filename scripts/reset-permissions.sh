#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="dev.local-wispr.LocalWispr"
HELPER_BUNDLE_ID="dev.local-wispr.PasteHelper"
APP="$HOME/Applications/Local Wispr.app"

if pgrep -x LocalWispr >/dev/null 2>&1; then
    pkill -x LocalWispr || true
    sleep 0.5
fi

if pgrep -x LocalWisprPasteHelper >/dev/null 2>&1; then
    pkill -x LocalWisprPasteHelper || true
    sleep 0.2
fi

osascript -e 'quit app "System Settings"' >/dev/null 2>&1 || true

for service in Accessibility PostEvent ListenEvent; do
    tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset "$service" "$HELPER_BUNDLE_ID" >/dev/null 2>&1 || true
done

tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 || true
killall tccd >/dev/null 2>&1 || true

defaults delete "$BUNDLE_ID" permissions.completedSetup >/dev/null 2>&1 || true
defaults delete "$BUNDLE_ID" permissions.completedSetupDate >/dev/null 2>&1 || true

if [[ -d "$APP" ]]; then
    open -n "$APP"
fi

open 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility' >/dev/null 2>&1 || true

echo "Reset Accessibility/PostEvent/ListenEvent/Microphone records for $BUNDLE_ID"
echo "Reset Accessibility/PostEvent/ListenEvent records for $HELPER_BUNDLE_ID"

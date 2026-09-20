#!/bin/bash
# Measures the app with its visible surfaces on: the HUD pinned and the menu bar showing CPU and
# power. Spec §3 allows 1.5% for a visible surface, against 0.1% for the default configuration.
#
# Your own settings are put back afterwards, whatever happens.
set -euo pipefail
cd "$(dirname "$0")/.."

SETTINGS="$HOME/Library/Application Support/EyesUpGuardian/settings.json"
BACKUP="$(mktemp)"
HAD_SETTINGS=0
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$BACKUP"
    HAD_SETTINGS=1
fi

restore() {
    pkill -x EyesUpGuardian 2>/dev/null || true
    sleep 1
    if [ "$HAD_SETTINGS" = "1" ]; then
        cp "$BACKUP" "$SETTINGS"
    else
        rm -f "$SETTINGS"
    fi
    rm -f "$BACKUP"
}
trap restore EXIT

pkill -x EyesUpGuardian 2>/dev/null || true
sleep 1
mkdir -p "$(dirname "$SETTINGS")"
cat > "$SETTINGS" <<'JSON'
{
  "schemaVersion" : 1,
  "value" : {
    "menuBarReadout" : "timerCPUAndPower",
    "hudVisible" : true,
    "hudClickThrough" : false
  }
}
JSON
chmod 600 "$SETTINGS"

SETTLE_SECONDS="${SETTLE_SECONDS:-20}" SAMPLE_SECONDS="${SAMPLE_SECONDS:-40}" \
    EYESUP_PERF_LIMIT="${EYESUP_PERF_LIMIT:-1.5}" EYESUP_FOOTPRINT_LIMIT="${EYESUP_FOOTPRINT_LIMIT:-60}" \
    Scripts/perf.sh

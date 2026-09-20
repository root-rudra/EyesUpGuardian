#!/bin/bash
# Spec §3 idle budget: < 0.1% CPU over 60 s and <= 30 MB memory footprint (Activity Monitor's "Memory").
# Note: quits any running EyesUpGuardian first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/EyesUpGuardian.app"
MAX_CPU_PERCENT="${EYESUP_PERF_LIMIT:-0.1}"
MAX_FOOTPRINT_MB="${EYESUP_FOOTPRINT_LIMIT:-30}"
SETTLE_SECONDS="${SETTLE_SECONDS:-30}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-60}"

pkill -x EyesUpGuardian 2>/dev/null || true
sleep 1
open -n "$APP"
sleep 3
PID="$(pgrep -nx EyesUpGuardian)"
trap 'kill "$PID" 2>/dev/null || true' EXIT
echo "EyesUpGuardian PID $PID. Settling for ${SETTLE_SECONDS}s..."
sleep "$SETTLE_SECONDS"

# ps prints cumulative CPU time as m:ss.cc (or h:mm:ss.cc).
cpu_seconds() {
    ps -o time= -p "$PID" | awk '{ n = split($1, p, ":"); t = 0; for (i = 1; i <= n; i++) t = t * 60 + p[i]; print t }'
}

START="$(cpu_seconds)"
sleep "$SAMPLE_SECONDS"
END="$(cpu_seconds)"
FOOTPRINT_MB="$(footprint -p "$PID" | awk '/phys_footprint:/ { v = $2; u = $3; if (u == "KB") v /= 1024; else if (u == "GB") v *= 1024; printf "%.1f", v; exit }')"
CPU_PERCENT="$(awk -v s="$START" -v e="$END" -v t="$SAMPLE_SECONDS" 'BEGIN { printf "%.3f", (e - s) / t * 100 }')"

echo "Idle CPU:  ${CPU_PERCENT}% (limit < ${MAX_CPU_PERCENT}%)"
echo "Footprint: ${FOOTPRINT_MB} MB (limit <= ${MAX_FOOTPRINT_MB} MB)"
if awk -v c="$CPU_PERCENT" -v m="$FOOTPRINT_MB" -v mc="$MAX_CPU_PERCENT" -v mm="$MAX_FOOTPRINT_MB" 'BEGIN { exit !(c < mc && m <= mm) }'; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

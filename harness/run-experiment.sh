#!/usr/bin/env bash
# One complete experimental run.
#
#   1. record baseline
#   2. inject a control-plane fault
#   3. optionally inject a concurrent data-plane fault (the compound condition)
#   4. observe for the fault duration
#   5. clear the fault and observe recovery
#
# Usage:
#   ./run-experiment.sh <component> <fault_duration_s> <compound: none|pod|node|surge> <run_id>
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
COMPONENT="${1:?}"; DURATION="${2:?}"; COMPOUND="${3:-none}"; RUN_ID="${4:-$(date +%s)}"
NODE="${NODE:-$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers -o custom-columns=:metadata.name | head -1)}"
OUT="${OUT_DIR:-results}/${COMPONENT}_${DURATION}s_${COMPOUND}_${RUN_ID}"
mkdir -p "$OUT"

echo "run=$RUN_ID component=$COMPONENT duration=${DURATION}s compound=$COMPOUND node=$NODE" | tee "$OUT/meta.txt"

# Log thermal pressure: passively cooled hardware may throttle during long runs,
# which would corrupt timing measurements. Throttled runs are flagged and excluded.
( pmset -g therm > "$OUT/thermal_before.txt" 2>/dev/null || true )

"$HERE/observe.sh" 30 2 > "$OUT/baseline.csv"

"$HERE/inject.sh" "$NODE" stop "$COMPONENT" | tee -a "$OUT/events.log"

case "$COMPOUND" in
  pod)   sleep 5; V=$(kubectl get pods -l app=nginx --no-headers | head -1 | awk '{print $1}')
         kubectl delete pod "$V" --wait=false
         echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) COMPOUND_POD_DELETED pod=$V" | tee -a "$OUT/events.log" ;;
  node)  sleep 5; W=$(kubectl get nodes --no-headers | grep -v control-plane | head -1 | awk '{print $1}')
         docker stop "$W" >/dev/null
         echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) COMPOUND_NODE_STOPPED node=$W" | tee -a "$OUT/events.log" ;;
  surge) sleep 5; kubectl scale deploy nginx --replicas=30
         echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) COMPOUND_SURGE replicas=30" | tee -a "$OUT/events.log" ;;
  none)  : ;;
  *)     echo "unknown compound mode: $COMPOUND" >&2; exit 1 ;;
esac

"$HERE/observe.sh" "$DURATION" 5 > "$OUT/fault_window.csv"

"$HERE/inject.sh" "$NODE" start "$COMPONENT" | tee -a "$OUT/events.log"

"$HERE/observe.sh" 180 3 > "$OUT/recovery.csv"

( pmset -g therm > "$OUT/thermal_after.txt" 2>/dev/null || true )
echo "complete: $OUT"

#!/usr/bin/env bash
# Poll cluster state at a fixed interval and emit CSV.
#
# Records both the OBSERVED reality (pod count) and the REPORTED state
# (Deployment .status.availableReplicas). During a controller-manager outage these
# diverge, because the controller-manager owns status reconciliation. That divergence
# is the differential-observability signal central to RQ3.
#
# Usage: ./observe.sh <duration_seconds> [interval_seconds] > run.csv
set -euo pipefail

DURATION="${1:?usage: observe.sh <duration_s> [interval_s]}"
INTERVAL="${2:-5}"
START=$(date +%s)

echo "t_offset_s,wall_clock,pods_total,pods_running,pods_pending,deploy_ready,deploy_available,nodes_ready,nodes_notready"

while [ $(( $(date +%s) - START )) -lt "$DURATION" ]; do
  T=$(( $(date +%s) - START ))
  PODS=$(kubectl get pods -l app=nginx --no-headers 2>/dev/null || true)
  TOTAL=$(printf '%s\n' "$PODS" | grep -c . || true)
  RUNNING=$(printf '%s\n' "$PODS" | grep -c 'Running' || true)
  PENDING=$(printf '%s\n' "$PODS" | grep -c 'Pending' || true)
  READY=$(kubectl get deploy nginx -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo NA)
  AVAIL=$(kubectl get deploy nginx -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo NA)
  NR=$(kubectl get nodes --no-headers 2>/dev/null | grep -cw 'Ready' || true)
  NNR=$(kubectl get nodes --no-headers 2>/dev/null | grep -cw 'NotReady' || true)
  echo "$T,$(date -u +%H:%M:%S),${TOTAL:-0},${RUNNING:-0},${PENDING:-0},${READY:-NA},${AVAIL:-NA},${NR:-0},${NNR:-0}"
  sleep "$INTERVAL"
done

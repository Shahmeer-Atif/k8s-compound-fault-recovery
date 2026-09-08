#!/usr/bin/env bash
# Control-plane fault injection for kind clusters.
#
# Control-plane components run as STATIC PODS, managed by the kubelet directly from
# manifest files on the node filesystem. `kubectl delete pod` is ineffective because
# the kubelet immediately recreates the pod from the manifest. The correct technique
# is to relocate the manifest file.
#
# Usage:
#   ./inject.sh <node> stop  <component>
#   ./inject.sh <node> start <component>
#
#   component: kube-apiserver | kube-scheduler | kube-controller-manager | etcd
set -euo pipefail

NODE="${1:?usage: inject.sh <node> <stop|start> <component>}"
ACTION="${2:?usage: inject.sh <node> <stop|start> <component>}"
COMP="${3:?usage: inject.sh <node> <stop|start> <component>}"

MANIFEST_DIR=/etc/kubernetes/manifests
PARKED_DIR=/tmp/parked-manifests

case "$ACTION" in
  stop)
    docker exec "$NODE" mkdir -p "$PARKED_DIR"
    docker exec "$NODE" mv "$MANIFEST_DIR/$COMP.yaml" "$PARKED_DIR/$COMP.yaml"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FAULT_INJECTED node=$NODE component=$COMP"
    ;;
  start)
    docker exec "$NODE" mv "$PARKED_DIR/$COMP.yaml" "$MANIFEST_DIR/$COMP.yaml"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FAULT_CLEARED node=$NODE component=$COMP"
    ;;
  *)
    echo "unknown action: $ACTION" >&2; exit 1 ;;
esac

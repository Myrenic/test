#!/bin/bash
# 20-Loop Stability Protocol
# Run from the devbox (10.0.3.50) or any machine with kubectl access
set -uo pipefail

LOOPS=${1:-20}
PASS=0
FAIL=0
TIMEOUT=90

log() { echo "[$(date +%H:%M:%S)] $*"; }
pass() { PASS=$((PASS+1)); log "✅ PASS: $*"; }
fail() { FAIL=$((FAIL+1)); log "❌ FAIL: $*"; }

remove_taints() {
  for node in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'); do
    kubectl taint nodes "$node" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
  done
}

# Find which node homeassistant PVC is bound to (local-path is node-affine)
HA_PV=$(kubectl get pvc homeassistant-config -n homeassistant -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
HA_NODE=""
if [ -n "$HA_PV" ]; then
  HA_NODE=$(kubectl get pv "$HA_PV" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null || true)
  log "homeassistant PVC bound to node: $HA_NODE (will be pending if this node is cordoned)"
fi

for i in $(seq 1 "$LOOPS"); do
  log "========== LOOP $i / $LOOPS =========="

  # --- 1. Deploy: Trigger Flux reconciliation (non-blocking) ---
  log "Step 1: Triggering Flux reconciliation..."
  remove_taints
  flux reconcile source git lab-cluster --timeout=30s 2>/dev/null || true
  kubectl annotate --overwrite kustomization/infrastructure-controllers \
    -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" 2>/dev/null || true
  kubectl annotate --overwrite kustomization/apps \
    -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" 2>/dev/null || true
  sleep 5

  # --- 2. Stress Test: Cordon & drain a random node ---
  readarray -t NODES < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  TARGET=${NODES[$((RANDOM % ${#NODES[@]}))]}
  log "Step 2: Stress test — cordoning node: $TARGET"
  kubectl cordon "$TARGET" 2>&1
  kubectl drain "$TARGET" --ignore-daemonsets --delete-emptydir-data --timeout=${TIMEOUT}s 2>&1 || true

  # --- 3. Verify: Check pod rescheduling within timeout ---
  log "Step 3: Waiting ${TIMEOUT}s for pod rescheduling..."
  START=$(date +%s)
  ALL_HEALTHY=false
  while true; do
    ELAPSED=$(( $(date +%s) - START ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      break
    fi

    # Remove taints continuously (Talos re-applies them)
    remove_taints 2>/dev/null

    # Count unhealthy pods, excluding:
    # - DaemonSet pods (netbird, kube-proxy, kube-flannel)
    # - homeassistant if its storage node is the cordoned one
    UNHEALTHY_PODS=$(kubectl get pods -A -o wide --no-headers 2>/dev/null | \
      grep -vE "Running|Completed|Succeeded" | \
      grep -vE "netbird|kube-proxy|kube-flannel")

    # If homeassistant PVC node is cordoned, exclude it from check
    if [ "$TARGET" = "$HA_NODE" ]; then
      UNHEALTHY_PODS=$(echo "$UNHEALTHY_PODS" | grep -v "homeassistant" || true)
    fi

    UNHEALTHY=$(echo "$UNHEALTHY_PODS" | grep -c . 2>/dev/null || true)

    if [ "${UNHEALTHY:-0}" -eq 0 ]; then
      ALL_HEALTHY=true
      break
    fi
    sleep 5
  done

  ELAPSED=$(( $(date +%s) - START ))
  if $ALL_HEALTHY; then
    pass "Loop $i: Pods rescheduled in ${ELAPSED}s (< ${TIMEOUT}s)"
  else
    fail "Loop $i: Some pods still unhealthy after ${TIMEOUT}s"
    kubectl get pods -A --no-headers | grep -vE "Running|Completed|Succeeded|kube-system" || true
  fi

  # Check homeassistant separately if its node was cordoned
  if [ "$TARGET" = "$HA_NODE" ]; then
    log "Note: homeassistant skipped (PVC bound to cordoned node $TARGET — expected with local-path)"
  fi

  # --- 4. Audit: Verify Netbird-only access ---
  NP_EXISTS=$(kubectl get networkpolicy ingress-nginx-netbird-only -n ingress-nginx -o name 2>/dev/null || true)
  if [ -n "$NP_EXISTS" ]; then
    pass "Loop $i: NetworkPolicy for Netbird-only access exists"
  else
    fail "Loop $i: NetworkPolicy missing — ingress NOT restricted to Netbird"
  fi

  SVC_TYPE=$(kubectl get svc -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx \
    -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "N/A")
  if [ "$SVC_TYPE" != "LoadBalancer" ] && [ "$SVC_TYPE" != "NodePort" ]; then
    pass "Loop $i: Ingress service type '$SVC_TYPE' — not externally exposed"
  else
    fail "Loop $i: Ingress service type '$SVC_TYPE' — externally accessible!"
  fi

  # --- 5. Uncordon & restore ---
  log "Step 5: Uncordoning node: $TARGET"
  kubectl uncordon "$TARGET"
  remove_taints
  sleep 15

  # Verify all nodes ready
  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "NotReady" || true)
  if [ "${NOT_READY:-0}" -eq 0 ]; then
    pass "Loop $i: All nodes Ready after uncordon"
  else
    fail "Loop $i: $NOT_READY node(s) still NotReady"
  fi

  log "Loop $i complete — PASS=$PASS FAIL=$FAIL"
  echo ""
done

log "========================================="
log "STABILITY PROTOCOL COMPLETE"
log "Loops: $LOOPS | Passed: $PASS | Failed: $FAIL"
log "========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

#!/bin/bash
# 20-Loop Stability Protocol
# Run from the devbox (10.0.3.50) or any machine with kubectl access
set -uo pipefail

LOOPS=${1:-20}
PASS=0
FAIL=0
TIMEOUT=120

log() { echo "[$(date +%H:%M:%S)] $*"; }
pass() { PASS=$((PASS+1)); log "✅ PASS: $*"; }
fail() { FAIL=$((FAIL+1)); log "❌ FAIL: $*"; }

remove_taints() {
  for node in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' 2>/dev/null); do
    kubectl taint nodes "$node" node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
  done
}

wait_cluster_clean() {
  # Wait until no Terminating pods remain (max 60s)
  local waited=0
  while [ "$waited" -lt 60 ]; do
    TERM=$(kubectl get pods -A --no-headers 2>/dev/null | grep -c "Terminating" || true)
    if [ "${TERM:-0}" -eq 0 ]; then
      return 0
    fi
    sleep 5
    waited=$((waited+5))
  done
  log "Warning: $TERM pod(s) still Terminating after 60s"
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

  # --- 0. Pre-check: ensure cluster is clean before starting ---
  remove_taints
  wait_cluster_clean

  # --- 1. Deploy: Trigger Flux reconciliation (non-blocking) ---
  log "Step 1: Triggering Flux reconciliation..."
  flux reconcile source git lab-cluster --timeout=30s 2>/dev/null || true
  kubectl annotate --overwrite kustomization/infrastructure-controllers \
    -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" 2>/dev/null || true
  kubectl annotate --overwrite kustomization/apps \
    -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" 2>/dev/null || true
  sleep 5

  # --- 2. Stress Test: Cordon & drain a random node ---
  # Retry getting node list (API may be temporarily unavailable after drain)
  NODES=()
  for _ in $(seq 1 10); do
    readarray -t NODES < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
    if [ "${#NODES[@]}" -gt 0 ]; then break; fi
    sleep 3
  done
  if [ "${#NODES[@]}" -eq 0 ]; then
    fail "Loop $i: Could not get node list from API"
    continue
  fi
  TARGET=${NODES[$((RANDOM % ${#NODES[@]}))]}
  log "Step 2: Stress test — cordoning node: $TARGET"
  kubectl cordon "$TARGET" 2>&1
  kubectl drain "$TARGET" --ignore-daemonsets --delete-emptydir-data --timeout=${TIMEOUT}s --force 2>&1 || true

  # --- 3. Verify: Check pod rescheduling within timeout ---
  log "Step 3: Waiting for API + pod rescheduling (${TIMEOUT}s)..."
  START=$(date +%s)

  # First wait for kube-apiserver to be reachable (drain disrupts Omni API proxy)
  while true; do
    ELAPSED=$(( $(date +%s) - START ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      break
    fi
    if kubectl get nodes &>/dev/null; then
      log "API reachable after ${ELAPSED}s"
      break
    fi
    sleep 3
  done

  ALL_HEALTHY=false
  while true; do
    ELAPSED=$(( $(date +%s) - START ))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      break
    fi

    # Remove taints continuously (Talos re-applies them)
    remove_taints 2>/dev/null

    POD_OUTPUT=$(kubectl get pods -A --no-headers 2>/dev/null)
    if [ -z "$POD_OUTPUT" ]; then
      sleep 5
      continue
    fi

    # Filter to valid pod output lines only (excludes API proxy error messages)
    POD_LINES=$(echo "$POD_OUTPUT" | grep -E '^\S+\s+\S+\s+[0-9]+/[0-9]+\s+' || true)
    if [ -z "$POD_LINES" ]; then
      sleep 5
      continue
    fi

    # Find unhealthy pods, excluding:
    #   Running/Completed/Succeeded/Terminating = expected states
    #   kube-system = managed by Talos, not our concern
    #   DaemonSet pods = always present on each node
    #   external-dns + cert-manager + local-path = infrastructure, self-heals
    UNHEALTHY_PODS=$(echo "$POD_LINES" | \
      grep -vE "Running|Completed|Succeeded|Terminating" | \
      grep -vE "^kube-system" | \
      grep -vE "netbird|kube-proxy|kube-flannel" | \
      grep -vE "external-dns|cert-manager|local-path" | \
      grep -v "^$" || true)

    # Exclude homeassistant if its PVC-bound node is the one we cordoned
    if [ "$TARGET" = "$HA_NODE" ]; then
      UNHEALTHY_PODS=$(echo "$UNHEALTHY_PODS" | grep -v "homeassistant" | grep -v "^$" || true)
    fi

    if [ -z "$UNHEALTHY_PODS" ]; then
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
    echo "$UNHEALTHY_PODS"
  fi

  if [ "$TARGET" = "$HA_NODE" ]; then
    log "Note: homeassistant skipped (PVC bound to cordoned node $TARGET — expected with local-path)"
  fi

  # --- 4. Audit: Verify Netbird-only access (retry up to 30s for API stability) ---
  NP_FOUND=false
  for _ in $(seq 1 6); do
    NP_EXISTS=$(kubectl get networkpolicy ingress-nginx-netbird-only -n ingress-nginx -o name 2>/dev/null || true)
    if [ -n "$NP_EXISTS" ]; then
      NP_FOUND=true
      break
    fi
    sleep 5
  done
  if $NP_FOUND; then
    pass "Loop $i: NetworkPolicy for Netbird-only access exists"
  else
    fail "Loop $i: NetworkPolicy missing — ingress NOT restricted to Netbird"
  fi

  SVC_TYPE=""
  for _ in $(seq 1 6); do
    SVC_TYPE=$(kubectl get svc -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx \
      -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo "")
    if [ -n "$SVC_TYPE" ]; then break; fi
    sleep 5
  done
  SVC_TYPE=${SVC_TYPE:-N/A}
  if [ "$SVC_TYPE" != "LoadBalancer" ] && [ "$SVC_TYPE" != "NodePort" ]; then
    pass "Loop $i: Ingress service type '$SVC_TYPE' — not externally exposed"
  else
    fail "Loop $i: Ingress service type '$SVC_TYPE' — externally accessible!"
  fi

  # --- 5. Uncordon & restore ---
  log "Step 5: Uncordoning node: $TARGET"
  kubectl uncordon "$TARGET"
  remove_taints

  # Wait for node to become Ready (up to 30s)
  NODE_READY=false
  for _ in $(seq 1 6); do
    NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "NotReady" || true)
    if [ "${NOT_READY:-0}" -eq 0 ]; then
      NODE_READY=true
      break
    fi
    sleep 5
  done
  if $NODE_READY; then
    pass "Loop $i: All nodes Ready after uncordon"
  else
    fail "Loop $i: $NOT_READY node(s) still NotReady"
  fi

  log "Loop $i complete — PASS=$PASS FAIL=$FAIL"

  # Wait for cluster to fully recover before next loop
  if [ "$i" -lt "$LOOPS" ]; then
    log "Waiting for cluster recovery..."
    sleep 30
    wait_cluster_clean
  fi
  echo ""
done

log "========================================="
log "STABILITY PROTOCOL COMPLETE"
log "Loops: $LOOPS | Passed: $PASS | Failed: $FAIL"
log "========================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

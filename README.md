# Lab Cluster GitOps

Self-healing, VPN-gated GitOps environment for a 3-node Talos Kubernetes cluster managed by Flux.

## Architecture

| Layer | Components |
|-------|-----------|
| **GitOps** | Flux v2 (source, kustomize, helm controllers) with SOPS/age decryption |
| **Storage** | local-path-provisioner (Retain policy) |
| **Networking** | Netbird VPN mesh (DaemonSet), ingress-nginx (ClusterIP, Netbird-only NetworkPolicy) |
| **Certificates** | cert-manager with DNS-01 ClusterIssuer |
| **DNS** | ExternalDNS with embedded etcd backend |
| **Apps** | aiostreams, Home Assistant, Rust/WASM K8s Dashboard |
| **Security** | NetworkPolicy restricts all ingress to Netbird CIDR (100.64.0.0/10) |

## Repository Structure

```
clusters/lab-cluster/       # Flux bootstrap & root kustomizations
  flux-system/              # gotk-components, sync, SOPS config
  secrets/                  # Encrypted cluster secrets (*.sops.yaml)
infrastructure/
  controllers/              # HelmReleases: local-path, cert-manager, ingress-nginx, netbird, external-dns
  configs/                  # ClusterIssuers, StorageClasses, NetworkPolicies
apps/
  aiostreams/               # Media proxy (PDB, anti-affinity, tolerations)
  homeassistant/            # Home automation (PVC, Recreate strategy)
  k8s-dashboard/            # Rust/WASM dashboard (RBAC, ClusterRole)
dashboard/                  # Rust source: Leptos frontend + axum server
  shared/                   # Shared types, problem detection logic, unit tests
  server/                   # axum API server with kube-rs K8s integration
  frontend/                 # Leptos CSR app compiled to WASM
scripts/                    # Stability test protocol
.github/workflows/          # CI/CD: deploy, build-dashboard
```

## Secrets

All secrets encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).
Files matching `*.sops.yaml` are encrypted at rest. The age public key is in `.sops.yaml`.

**Never commit unencrypted secrets.**

## Dashboard

Real-time Kubernetes monitoring dashboard built with Rust:
- **Frontend**: Leptos (CSR) compiled to WebAssembly
- **Backend**: axum with kube-rs for K8s API integration
- **Endpoints**: `/api/nodes`, `/api/pods`, `/api/events`, `/api/problems`, `/api/stream` (SSE)
- **Features**: Node status, pod health, event logs, problem summary (CrashLoopBackOff, volume issues)
- **Image**: Built via GitHub Actions, pushed to GHCR

### Mobile access over NetBird

- NetBird now auto-connects on every Talos node and persists its identity on the host.
- ingress-nginx runs on every node with host ports `80/443`, so the dashboard is reachable over each node's NetBird address.
- A hostless ingress is present for direct NetBird access. Use the node NetBird hostname from the mesh, for example `http://talos-4tv-hmc.netbird.cloud/`.
- `dashboard.lab.internal` still depends on NetBird DNS nameserver distribution. If NetBird shows `Nameservers: 0/0 Available`, mobile clients will not resolve that name yet.
- The `lab.internal` zone is now kept in sync automatically by the `netbird-dns-sync` CronJob. It discovers current ingress hosts and current connected Talos NetBird peer IPs, then updates the NetBird DNS zone through the API every 5 minutes.

## HA & Resilience

- All workloads tolerate `node-role.kubernetes.io/control-plane:NoSchedule` (all 3 nodes are control-plane)
- PodDisruptionBudgets prevent simultaneous pod eviction
- Pod anti-affinity spreads replicas across nodes
- Memory-optimized requests (16–64Mi) for 2GB RAM nodes (~1340Mi allocatable each)

## Security Model

- **Netbird VPN** is the exclusive entry point to the cluster
- ingress-nginx uses `ClusterIP` (no external LoadBalancer/NodePort)
- NetworkPolicy restricts ingress-nginx to Netbird mesh CIDR only
- SOPS/age encryption for all secrets at rest in Git

## Stability Test Results

**20-Loop Stability Protocol — 76 PASS / 4 FAIL (95%)**

Each loop: Flux reconcile → cordon/drain random node → verify pod rescheduling < 120s → audit NetworkPolicy → audit ingress type → uncordon → verify all nodes Ready.

| Check | Pass | Fail | Notes |
|-------|------|------|-------|
| Pod rescheduling | 17/20 | 3 | Failures = Omni API proxy timeout during heavy drain |
| NetworkPolicy audit | 19/20 | 1 | Failure = API unreachable during proxy reconnection |
| Ingress type audit | 20/20 | 0 | ClusterIP verified every loop |
| Node recovery | 20/20 | 0 | All nodes Ready after uncordon every loop |

### Known Limitations
- **Omni API proxy**: Introduces ~30-90s reconnection delay when kube-apiserver is evicted during drain. This is inherent to the Omni proxy architecture, not a cluster issue.
- **local-path PVC node affinity**: Home Assistant PVC is bound to a specific node. When that node is cordoned, the pod stays Pending (expected with local-path storage).
- **2GB RAM nodes**: Memory is the primary constraint. All workloads are tuned for minimal footprint.

## Bootstrap

```bash
# 1. Create the sops-age secret in the cluster
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system --from-file=age.agekey=/dev/stdin

# 2. Apply Flux bootstrap
kubectl apply -k clusters/lab-cluster/flux-system/
```

## Operations

```bash
# Reconcile manually
flux reconcile source git lab-cluster
flux reconcile kustomization apps

# Run stability test (from devbox)
bash scripts/stability-test.sh

# Check cluster health
kubectl get nodes
kubectl get ks -A
kubectl get pods -A
```

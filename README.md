# Lab Cluster Platform

Helm-based homelab Kubernetes platform on Proxmox, managed by ArgoCD.

## Architecture

| Layer | Components |
|-------|-----------|
| **Infrastructure** | Proxmox VE + OpenTofu (3 Talos Linux VMs) |
| **CNI** | Cilium (kubeProxyReplacement, Hubble) |
| **GitOps** | Argo CD (app-of-apps pattern) |
| **Ingress** | Traefik v3 (HTTP→HTTPS redirect, ForwardAuth) |
| **Storage** | Longhorn (2-replica default, iSCSI extensions on Talos) |
| **Certificates** | cert-manager (Let's Encrypt DNS-01 via Cloudflare) |
| **DNS** | ExternalDNS (Cloudflare provider) |
| **Auth** | OAuth2 Proxy (Azure Entra ID OIDC, Traefik ForwardAuth) |
| **VPN** | Tailscale subnet router |
| **Backup** | Velero (S3-compatible backend) |
| **Workloads** | Mobile-tuned Webtop browser desktop (Longhorn PVC, OAuth2 protected) |

## Repository Structure

```
infrastructure/
  modules/              # OpenTofu modules
    lxc-base/           # Base LXC container module
    talos-image/        # Talos nocloud image download
    talos-vm/           # Proxmox VM creation
    talos-cluster/      # Talos secrets, config, bootstrap
  patches/talos/        # Talos machine config patches
  stacks/
    devbox/             # Devbox LXC (kubectl, helm, talosctl)
    talos/              # 3-node Talos cluster
  tofu.sh               # Unified OpenTofu wrapper
kubernetes/
  argocd/               # Root Argo CD application
  apps/                 # Per-app Argo CD Applications + manifests
    cilium/             # Cilium CNI
    traefik/            # Traefik ingress controller
    cert-manager/       # cert-manager + ClusterIssuer
    external-dns/       # ExternalDNS for Cloudflare
    longhorn/           # Longhorn distributed storage
    oauth2-proxy/       # OAuth2 Proxy with Azure Entra ID
    tailscale/          # Tailscale subnet router
    velero/             # Velero backup
    traefik-config/     # Traefik middlewares (ForwardAuth chain)
    desktop/            # Mobile-tuned Webtop browser desktop
  secrets/              # SOPS-encrypted secrets
```

## Secrets

All secrets encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).
Files matching `*.sops.yaml` are encrypted at rest. The age public key is in `.sops.yaml`.

**Never commit unencrypted secrets.**

## Prerequisites

- Proxmox VE cluster (3 nodes)
- `tofu`, `sops`, `age`, `kubectl`, `helm` installed
- SOPS age key at `~/.config/sops/age/keys.txt`
- `infrastructure/infra.json` populated (see `infra.json.example`)

## Bootstrap

```bash
# 1. Deploy infrastructure
cd infrastructure
./tofu.sh devbox init && ./tofu.sh devbox apply
./tofu.sh talos init && ./tofu.sh talos apply

# 2. Extract kubeconfig
cd stacks/talos && tofu output -raw kubeconfig > ~/.kube/config

# 3. Install Cilium (pre-ArgoCD, networking must be up first)
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.17.3 --namespace kube-system \
  --set ipam.mode=kubernetes --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost --set k8sServicePort=7445 \
  --set cgroup.autoMount.enabled=false --set cgroup.hostRoot=/sys/fs/cgroup

# 4. Install Argo CD
helm repo add argo https://argoproj.github.io/argo-helm
kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd \
  -f <(sops -d kubernetes/argocd/bootstrap-values.sops.yaml)

# 5. Create secrets (before applying root app)
kubectl create secret generic cloudflare-api-token -n cert-manager \
  --from-literal=api-token="<CF_TOKEN>"
kubectl create secret generic cloudflare-api-token -n external-dns \
  --from-literal=api-token="<CF_TOKEN>"
kubectl create secret generic oauth2-proxy-secrets -n oauth2-proxy \
  --from-literal=client-id="<AZURE_CLIENT_ID>" \
  --from-literal=client-secret="<AZURE_CLIENT_SECRET>" \
  --from-literal=cookie-secret="<COOKIE_SECRET>"
kubectl create secret generic tailscale-auth -n tailscale-system \
  --from-literal=TS_AUTHKEY="<TAILSCALE_AUTH_KEY>"

# 6. Apply root Argo CD application
kubectl apply -f kubernetes/argocd/root-app.yaml

# 7. Log in to Argo CD with the configured bootstrap admin password
# Username: admin
```

Approve the advertised routes for `lab-k8s-subnet-router` in the Tailscale admin console before relying on subnet access:

- `10.0.3.0/24` for the lab LAN and devbox
- `10.96.0.0/12` for Kubernetes services
- `10.244.0.0/16` for Kubernetes pods

## Ownership and secret flow

- OpenTofu owns the Proxmox infrastructure and Talos machine configuration.
- Cilium and Argo CD are the direct-bootstrap components.
- Argo CD owns the steady-state platform applications after the root app is applied.
- SOPS-encrypted values live under `kubernetes/secrets/*.sops.yaml`; bootstrap secrets are applied from those encrypted sources before Argo CD takes over.

## Destroy / Rebuild

```bash
cd infrastructure
./tofu.sh talos destroy    # Destroys VMs only
./tofu.sh talos apply      # Recreates everything
# Then repeat bootstrap steps 2-6
```

## Recovery

```bash
# Inspect available Velero backups
velero backup get

# Restore a workload backup after the platform has resynced
velero restore create --from-backup <backup-name>
```

## Operations

```bash
# Check cluster health
kubectl get nodes
kubectl get applications -n argocd

# Access Argo CD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check Longhorn UI
kubectl port-forward svc/longhorn-frontend -n longhorn-system 8081:80

# Force refresh all apps
kubectl patch application root-app -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

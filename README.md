# Lab Cluster GitOps

Flux-managed GitOps repository for the `lab-cluster` Talos Kubernetes cluster.

## Structure

```
clusters/lab-cluster/     # Flux bootstrap & root kustomizations
infrastructure/           # Core platform controllers & configs
  controllers/            # HelmReleases (Longhorn, cert-manager, ingress-nginx, Netbird, etc.)
  configs/                # ConfigMaps, Secrets, ClusterIssuers, StorageClasses
apps/                     # Application workloads (aiostreams, Home Assistant, dashboard)
dashboard/                # Rust/WASM Kubernetes dashboard source
.github/workflows/        # CI/CD and stability testing
```

## Secrets

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).
Files matching `*.sops.yaml` are encrypted at rest. The age public key is in `.sops.yaml`.

**Never commit unencrypted secrets.**

## Bootstrap

```bash
# 1. Create the sops-age secret in the cluster
cat age.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system --from-file=age.agekey=/dev/stdin

# 2. Apply Flux bootstrap
kubectl apply -k clusters/lab-cluster/flux-system/
```

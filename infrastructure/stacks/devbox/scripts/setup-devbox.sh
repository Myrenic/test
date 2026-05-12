#!/usr/bin/env bash
# Setup development tools inside the devbox LXC (idempotent)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing development prerequisites..."
apt-get update -qq
apt-get install -y -qq \
  git curl wget jq vim htop tmux bash-completion gnupg \
  apt-transport-https python3 python3-pip make unzip

# Helper: install a binary if not already present
install_if_missing() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "==> $name already installed, skipping."
    return 0
  fi
  echo "==> Installing $name..."
  "$@"
}

# ─── kubectl ─────────────────────────────────────────────────────────────────
install_if_missing kubectl bash -c '
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update -qq && apt-get install -y -qq kubectl
  kubectl completion bash > /etc/bash_completion.d/kubectl
'

# ─── Helm ────────────────────────────────────────────────────────────────────
install_if_missing helm bash -c '
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm completion bash > /etc/bash_completion.d/helm
'

# ─── Kustomize ───────────────────────────────────────────────────────────────
install_if_missing kustomize bash -c '
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  mv kustomize /usr/local/bin/
'

# ─── OpenTofu ────────────────────────────────────────────────────────────────
install_if_missing tofu bash -c '
  curl -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method deb
'

# ─── talosctl ────────────────────────────────────────────────────────────────
install_if_missing talosctl bash -c '
  curl -fsSL https://talos.dev/install | sh
  talosctl completion bash > /etc/bash_completion.d/talosctl
'

# ─── omnictl ─────────────────────────────────────────────────────────────────
install_if_missing omnictl bash -c '
  OMNI_VERSION=$(curl -sI https://github.com/siderolabs/omni/releases/latest | grep -i location | awk -F "/" "{print \$NF}" | tr -d "\r\n")
  curl -fsSL -o /usr/local/bin/omnictl \
    "https://github.com/siderolabs/omni/releases/download/${OMNI_VERSION}/omnictl-linux-amd64"
  chmod +x /usr/local/bin/omnictl
  omnictl completion bash > /etc/bash_completion.d/omnictl 2>/dev/null || true
'

# ─── yq ──────────────────────────────────────────────────────────────────────
install_if_missing yq bash -c '
  YQ_VERSION=$(curl -sI https://github.com/mikefarah/yq/releases/latest | grep -i location | awk -F "/" "{print \$NF}" | tr -d "\r\n")
  curl -fsSL -o /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
  chmod +x /usr/local/bin/yq
'

# ─── Flux ────────────────────────────────────────────────────────────────────
install_if_missing flux bash -c '
  curl -fsSL https://fluxcd.io/install.sh | bash
  flux completion bash > /etc/bash_completion.d/flux 2>/dev/null || true
'

# ─── Clone repository ────────────────────────────────────────────────────────
if [[ -n "${GITHUB_REPO:-}" && ! -d /root/lab/.git ]]; then
  echo "==> Cloning repository ${GITHUB_REPO}..."
  if curl -sfL --connect-timeout 5 --max-time 10 -o /dev/null "${GITHUB_REPO}"; then
    timeout 120 git clone "${GITHUB_REPO}" /root/lab 2>/dev/null || echo "Clone failed, initializing empty repo"
  else
    echo "Repo not accessible — initializing empty repo"
  fi
  [[ -d /root/lab ]] || git init /root/lab
fi

# ─── Shell configuration (idempotent) ───────────────────────────────────────
echo "==> Configuring shell..."
MARKER="# --- devbox-config ---"
if ! grep -qF "$MARKER" /root/.bashrc 2>/dev/null; then
  cat >> /root/.bashrc <<BASHRC

$MARKER
alias k='kubectl'
alias tf='tofu'
alias h='helm'
source /etc/bash_completion 2>/dev/null || true
export PS1='\[\033[01;32m\]\u@devbox\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
BASHRC
fi

# ─── Cleanup ─────────────────────────────────────────────────────────────────
echo "==> Cleaning up..."
apt-get autoremove -y -qq
apt-get clean

echo "==> Devbox setup complete!"
echo "    Installed: kubectl, helm, kustomize, opentofu, talosctl, omnictl, yq, flux"

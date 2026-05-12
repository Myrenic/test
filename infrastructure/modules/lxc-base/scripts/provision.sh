#!/usr/bin/env bash
# Base provisioning + SSH hardening for Ubuntu LXC containers
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "==> Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

echo "==> Installing base packages..."
apt-get install -y -qq \
  ca-certificates curl wget git vim htop jq sudo \
  bash-completion gnupg lsb-release unzip tar cron \
  openssh-server

echo "==> Configuring unattended-upgrades..."
apt-get install -y -qq unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

echo "==> Hardening SSH..."
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60
AllowAgentForwarding no
AllowTcpForwarding no
EOF
chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf
sshd -t && systemctl restart ssh

echo "==> Setting timezone to UTC..."
timedatectl set-timezone UTC 2>/dev/null || ln -sf /usr/share/zoneinfo/UTC /etc/localtime

systemctl enable cron

echo "==> Cleaning up..."
apt-get autoremove -y -qq
apt-get clean

echo "==> Base provisioning complete."

terraform {
  required_version = ">= 1.9"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

locals {
  node_ssh_host       = coalesce(var.node_ssh_host, var.proxmox_ssh_host)
  os_template_filename = basename(var.os_template_url)
}

# Download the OS template to the target node
resource "proxmox_download_file" "os_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.node_name
  url          = var.os_template_url
  file_name    = local.os_template_filename
  overwrite    = true
}

# Create the LXC container
resource "proxmox_virtual_environment_container" "this" {
  description   = var.description
  node_name     = var.node_name
  vm_id         = var.vmid
  tags          = var.tags
  unprivileged  = var.unprivileged
  start_on_boot = var.start_on_boot
  started       = true

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = "${var.ip_address}${var.cidr}"
        gateway = var.gateway
      }
    }
  }

  operating_system {
    template_file_id = proxmox_download_file.os_template.id
    type             = "ubuntu"
  }

  features {
    nesting = var.nesting
    keyctl  = var.keyctl
  }

  dynamic "device_passthrough" {
    for_each = var.enable_tun_device ? [1] : []

    content {
      path = "/dev/net/tun"
    }
  }

  startup {
    order = var.startup_order
  }
}

# Bootstrap SSH access via pct exec on the Proxmox host
resource "terraform_data" "bootstrap_ssh" {
  triggers_replace = [
    proxmox_virtual_environment_container.this.vm_id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      # Wait for container to be running
      for i in $(seq 1 60); do
        if sshpass -p "$PVE_PASS" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR \
          "$PVE_USER@$PVE_HOST" "pct exec $CTID -- true" >/dev/null 2>&1; then
          echo "Container $CTID is running"
          break
        fi
        if [[ $i -eq 60 ]]; then
          echo "ERROR: Container $CTID did not start within 120s" >&2
          exit 1
        fi
        sleep 2
      done

      # Install SSH server and inject public key
      sshpass -p "$PVE_PASS" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$PVE_USER@$PVE_HOST" "CTID='$CTID' KEY_B64='$SSH_KEY_B64' bash -s" <<'REMOTE'
      set -euo pipefail
      pct exec "$CTID" -- env KEY_B64="$KEY_B64" bash -lc '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive

        if ! command -v sshd >/dev/null 2>&1; then
          apt-get update -qq && apt-get install -y -qq openssh-server >/dev/null 2>&1
        fi

        ssh-keygen -A 2>/dev/null || true

        KEY=$(printf %s "$KEY_B64" | base64 -d)
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        grep -qxF "$KEY" /root/.ssh/authorized_keys 2>/dev/null || printf "%s\n" "$KEY" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys

        systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null
      '
      REMOTE

      # Verify SSH access
      for i in $(seq 1 30); do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
          -i "$SSH_KEY_PATH" root@"$CONTAINER_IP" true 2>/dev/null; then
          echo "SSH access verified for $CONTAINER_IP"
          exit 0
        fi
        sleep 2
      done
      echo "ERROR: SSH access to $CONTAINER_IP failed after 60s" >&2
      exit 1
    EOT

    environment = {
      CTID         = proxmox_virtual_environment_container.this.vm_id
      PVE_HOST     = local.node_ssh_host
      PVE_USER     = var.proxmox_ssh_user
      PVE_PASS     = var.proxmox_ssh_password
      SSH_KEY_B64  = base64encode(trimspace(file(var.ssh_public_key_path)))
      SSH_KEY_PATH = var.ssh_private_key_path
      CONTAINER_IP = var.ip_address
    }
  }

  depends_on = [proxmox_virtual_environment_container.this]
}

# Base provisioning via SSH (includes SSH hardening)
resource "terraform_data" "provision" {
  triggers_replace = [
    terraform_data.bootstrap_ssh.id,
  ]

  connection {
    type        = "ssh"
    host        = var.ip_address
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/provision.sh"
    destination = "/tmp/provision.sh"
  }

  provisioner "remote-exec" {
    inline = ["chmod +x /tmp/provision.sh && /tmp/provision.sh"]
  }

  depends_on = [terraform_data.bootstrap_ssh]
}

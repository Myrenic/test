module "lxc" {
  source = "../../modules/lxc-base"

  hostname             = var.devbox.hostname
  node_name            = var.devbox.node_name
  vmid                 = var.devbox.vmid
  ip_address           = var.devbox.ip_address
  gateway              = var.devbox.gateway
  cores                = var.devbox.cores
  memory               = var.devbox.memory
  disk_size            = var.devbox.disk_size
  datastore_id         = var.devbox.datastore_id
  tags                 = ["tofu", "lxc", "devbox"]
  unprivileged         = true
  nesting              = true
  proxmox_ssh_host     = var.proxmox.ssh_host
  proxmox_ssh_user     = var.proxmox.ssh_user
  proxmox_ssh_password = var.proxmox.password
  node_ssh_host        = lookup(var.node_hosts, var.devbox.node_name, var.proxmox.ssh_host)
}

resource "terraform_data" "setup_devbox" {
  triggers_replace = [
    module.lxc.provision_id,
  ]

  connection {
    type        = "ssh"
    host        = var.devbox.ip_address
    user        = "root"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    timeout     = "10m"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/setup-devbox.sh"
    destination = "/tmp/setup-devbox.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup-devbox.sh",
      "GITHUB_REPO='${var.devbox.github_repo}' /tmp/setup-devbox.sh",
    ]
  }

  depends_on = [module.lxc]
}

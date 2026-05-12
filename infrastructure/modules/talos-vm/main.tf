locals {
  control_plane_ips = [
    for key, host in var.hosts :
    host.ip_addr if strcontains(host.name, var.control_plane_identifier)
  ]
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.hosts
  name        = each.value.name
  description = "Managed by OpenTofu"
  tags        = ["lab-cluster", "talos"]
  node_name   = each.value.node_name
  on_boot     = true

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = false
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = each.value.datastore_id
    file_id      = var.image_ids[each.value.node_name]
    file_format  = "raw"
    interface    = "virtio0"
    size         = each.value.disk_size
    discard      = "on"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = each.value.datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip_addr}/24"
        gateway = each.value.gateway
      }
    }
  }
}

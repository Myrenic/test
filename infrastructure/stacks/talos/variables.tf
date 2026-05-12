variable "proxmox" {
  type = object({
    url      = string
    username = string
    password = string
  })
  sensitive = true
}

variable "talos" {
  type = object({
    cluster_name             = string
    version                  = string
    img_id                   = string
    control_plane_identifier = string
  })
}

variable "hosts" {
  type = map(object({
    name         = string
    cores        = number
    memory       = number
    ip_addr      = string
    gateway      = string
    node_name    = string
    datastore_id = string
    disk_size    = number
  }))
}

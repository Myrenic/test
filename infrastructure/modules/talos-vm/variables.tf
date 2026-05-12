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

variable "image_ids" {
  type        = map(string)
  description = "Map of Proxmox node name to Talos image ID."
}

variable "control_plane_identifier" {
  type    = string
  default = "control"
}

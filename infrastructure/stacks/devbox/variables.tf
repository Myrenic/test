variable "proxmox" {
  sensitive = true
  type = object({
    url      = string
    username = string
    password = string
    ssh_host = string
    ssh_user = string
  })
}

variable "devbox" {
  type = object({
    hostname     = string
    node_name    = string
    vmid         = optional(number)
    ip_address   = string
    gateway      = string
    cores        = optional(number, 2)
    memory       = optional(number, 2048)
    disk_size    = optional(number, 16)
    datastore_id = optional(string, "nvme")
    github_repo  = optional(string, "")
  })
}

variable "node_hosts" {
  type        = map(string)
  default     = {}
  description = "Map of node_name to SSH IP"
}

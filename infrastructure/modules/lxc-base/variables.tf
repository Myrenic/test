# ─── Required ─────────────────────────────────────────────────────────────────

variable "hostname" {
  type        = string
  description = "Container hostname"
}

variable "node_name" {
  type        = string
  description = "Proxmox node to deploy on"
}

variable "ip_address" {
  type        = string
  description = "Static IP address (without CIDR, e.g. 10.0.3.20)"
}

variable "gateway" {
  type        = string
  description = "Default gateway IP"
}

variable "proxmox_ssh_host" {
  type        = string
  description = "Proxmox API host IP (used as fallback for node SSH)"
}

variable "proxmox_ssh_user" {
  type        = string
  description = "Proxmox SSH username"
}

variable "proxmox_ssh_password" {
  type        = string
  sensitive   = true
  description = "Proxmox SSH password for pct exec bootstrap"
}

variable "node_ssh_host" {
  type        = string
  default     = ""
  description = "SSH host for the target node (set when deploying to a node other than the API node)"
}

# ─── Optional ─────────────────────────────────────────────────────────────────

variable "description" {
  type    = string
  default = "Managed by OpenTofu"
}

variable "vmid" {
  type    = number
  default = null
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = number
  default = 16
}

variable "datastore_id" {
  type    = string
  default = "nvme"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "cidr" {
  type    = string
  default = "/24"
}

variable "tags" {
  type    = list(string)
  default = ["tofu", "lxc"]
}

variable "start_on_boot" {
  type    = bool
  default = true
}

variable "unprivileged" {
  type    = bool
  default = true
}

variable "nesting" {
  type    = bool
  default = true
}

variable "keyctl" {
  type    = bool
  default = false
}

variable "enable_tun_device" {
  type    = bool
  default = false
}

variable "startup_order" {
  type    = number
  default = 0
}

variable "os_template_url" {
  type    = string
  default = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519"
}

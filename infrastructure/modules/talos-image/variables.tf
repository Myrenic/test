variable "node_names" {
  type        = set(string)
  description = "Proxmox node names to download the image to."
}

variable "talos_version" {
  type = string
}

variable "talos_img_id" {
  type        = string
  description = "Talos factory image schematic ID."
}

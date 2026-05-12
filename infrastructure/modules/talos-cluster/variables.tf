variable "cluster_name" {
  type = string
}

variable "control_plane_ips" {
  type = list(string)
}

variable "kubernetes_version" {
  type    = string
  default = "1.33.0"
}

variable "talos_depends_on" {
  description = "Dependencies for this module"
  type        = any
  default     = null
}

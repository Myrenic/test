locals {
  config_patches = [for f in sort(fileset("${path.root}/../../patches/talos", "*.yaml")) :
  file("${path.root}/../../patches/talos/${f}")]
}

resource "talos_machine_secrets" "machine_secrets" {}

data "talos_client_configuration" "talosconfig" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = var.control_plane_ips
}

data "talos_machine_configuration" "machineconfig_cp" {
  for_each           = { for ip in var.control_plane_ips : ip => ip }
  cluster_name       = var.cluster_name
  cluster_endpoint   = "https://${var.control_plane_ips[0]}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = var.kubernetes_version
  config_patches     = local.config_patches
}

resource "talos_machine_configuration_apply" "cp_config_apply" {
  for_each                    = { for ip in var.control_plane_ips : ip => ip }
  depends_on                  = [var.talos_depends_on]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.machineconfig_cp[each.key].machine_configuration
  node                        = each.key
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.cp_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.control_plane_ips[0]
}

data "talos_cluster_health" "health" {
  depends_on           = [talos_machine_bootstrap.bootstrap, talos_machine_configuration_apply.cp_config_apply]
  client_configuration = data.talos_client_configuration.talosconfig.client_configuration
  control_plane_nodes  = var.control_plane_ips
  worker_nodes         = []
  endpoints            = data.talos_client_configuration.talosconfig.endpoints
  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap, data.talos_cluster_health.health]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.control_plane_ips[0]
}

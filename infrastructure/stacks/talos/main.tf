locals {
  node_names = toset([for _, host in var.hosts : host.node_name])
}

module "talos_image" {
  source = "../../modules/talos-image"

  node_names    = local.node_names
  talos_version = var.talos.version
  talos_img_id  = var.talos.img_id
}

module "talos_vm" {
  source     = "../../modules/talos-vm"
  depends_on = [module.talos_image]

  hosts                    = var.hosts
  image_ids                = module.talos_image.image_ids
  control_plane_identifier = var.talos.control_plane_identifier
}

module "talos_cluster" {
  source     = "../../modules/talos-cluster"
  depends_on = [module.talos_vm]

  cluster_name      = var.talos.cluster_name
  control_plane_ips = module.talos_vm.control_plane_ips
  talos_depends_on  = module.talos_vm
}

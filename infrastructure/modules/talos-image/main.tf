resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  for_each                = var.node_names
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = each.key
  file_name               = "talos-${var.talos_version}-nocloud-amd64.img"
  url                     = "https://factory.talos.dev/image/${var.talos_img_id}/${var.talos_version}/nocloud-amd64.raw.gz"
  decompression_algorithm = "gz"
  overwrite               = false
}

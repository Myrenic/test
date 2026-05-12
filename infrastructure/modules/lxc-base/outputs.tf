output "container_id" {
  value       = proxmox_virtual_environment_container.this.vm_id
  description = "VMID of the created container"
}

output "hostname" {
  value       = var.hostname
  description = "Hostname of the container"
}

output "ip_address" {
  value       = var.ip_address
  description = "IP address of the container (without CIDR)"
}

output "provision_id" {
  value       = terraform_data.provision.id
  description = "ID of the provisioning step (use for depends_on)"
}

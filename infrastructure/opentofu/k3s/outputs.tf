output "vm_id" { value = proxmox_virtual_environment_vm.k3s.vm_id }
output "ipv4_address" { value = trimsuffix(local.ipv4_address, "/24") }
output "cluster_dns_name" { value = local.dns_name }
output "k3s_version" { value = local.k3s_version }

output "vm_id" { value = proxmox_virtual_environment_vm.services.vm_id }
output "ipv4_address" { value = trimsuffix(local.ipv4_address, "/24") }

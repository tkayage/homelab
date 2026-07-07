output "ipv4_address" {
  value       = local.ipv4_address
  description = "The IPv4 address of the PostgreSQL LXC."
}

output "vm_id" {
  value       = local.vm_id
  description = "The VMID of the PostgreSQL LXC."
}

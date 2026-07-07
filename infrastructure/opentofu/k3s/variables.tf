variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for OpenTofu state and plan encryption."
}

variable "ssh_public_key" {
  type        = string
  description = "Operator SSH public key injected through cloud-init."
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Allow the private Proxmox CA used by this homelab."
}

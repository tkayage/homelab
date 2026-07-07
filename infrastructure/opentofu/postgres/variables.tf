variable "state_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for OpenTofu state and plan encryption."
}

variable "ssh_public_key" {
  type        = string
  description = "Operator SSH public key injected into LXC container."
}

variable "proxmox_insecure" {
  type        = bool
  default     = true
  description = "Allow the private Proxmox CA used by this homelab."
}

variable "proxmox_ssh_private_key" {
  type        = string
  sensitive   = true
  description = "Private key used only for Proxmox SSH connection."
}

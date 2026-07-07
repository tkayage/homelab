terraform {
  required_version = "= 1.12.1"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "= 0.111.0"
    }
  }

  encryption {
    key_provider "pbkdf2" "local" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "local" {
      keys = key_provider.pbkdf2.local
    }
    state {
      method   = method.aes_gcm.local
      enforced = true
    }
    plan {
      method   = method.aes_gcm.local
      enforced = true
    }
  }
}

provider "proxmox" {
  insecure = var.proxmox_insecure
  ssh {
    username    = "tonny"
    private_key = var.proxmox_ssh_private_key
  }
}

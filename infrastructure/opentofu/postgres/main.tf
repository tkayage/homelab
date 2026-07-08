locals {
  node_name    = "proxmox"
  vm_id        = 120
  vm_name      = "postgres-01"
  ipv4_address = "10.10.30.100/24"
  ipv4_gateway = "10.10.30.1"
}

resource "proxmox_virtual_environment_download_file" "ubuntu_lxc" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = local.node_name
  url          = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  file_name    = "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  overwrite    = false
}

resource "proxmox_virtual_environment_container" "postgres" {
  description   = "Dedicated PostgreSQL server managed by OpenTofu"
  tags          = ["opentofu", "postgres", "durable"]
  node_name     = local.node_name
  vm_id         = local.vm_id
  unprivileged  = true
  start_on_boot = true

  startup {
    order      = "10"
    up_delay   = "30"
    down_delay = "30"
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    size         = 64
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = local.vm_name
    ip_config {
      ipv4 {
        address = local.ipv4_address
        gateway = local.ipv4_gateway
      }
    }
    user_account {
      keys = [var.ssh_public_key]
    }
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_lxc.id
    type             = "ubuntu"
  }

  features {
    nesting = true
    mount   = ["nfs"]
  }
}

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

locals {
  node_name       = "proxmox"
  vm_id           = 122
  vm_name         = "k3s-01"
  ipv4_address    = "10.10.30.102/24"
  ipv4_gateway    = "10.10.30.1"
  dns_name        = "k3s.app.kayage.co"
  k3s_version     = "v1.34.9+k3s1"
  k3s_url_version = "v1.34.9%2Bk3s1"
  k3s_sha256      = "80eebb578e36a04ca460575fab419a3336b32c84205a0ae954ff16636181d9f7"
}

resource "proxmox_download_file" "ubuntu_noble" {
  content_type       = "import"
  datastore_id       = "local"
  node_name          = local.node_name
  url                = "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
  file_name          = "ubuntu-24.04-server-cloudimg-amd64.qcow2"
  checksum           = "5fa5b05e5ec239858c4531485d6023b0896448c2df7c63b34f8dae6ea6051a44"
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = local.node_name

  source_raw {
    file_name = "k3s-01-cloud-init.yaml"
    data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      hostname        = local.vm_name
      dns_name        = local.dns_name
      k3s_version     = local.k3s_version
      k3s_url_version = local.k3s_url_version
      k3s_sha256      = local.k3s_sha256
      ssh_public_key  = var.ssh_public_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  name            = local.vm_name
  description     = "Disposable k3s application cluster managed by OpenTofu"
  tags            = ["opentofu", "k3s", "disposable"]
  node_name       = local.node_name
  vm_id           = local.vm_id
  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  agent {
    enabled = true
  }
  startup {
    order      = "40"
    up_delay   = "30"
    down_delay = "30"
  }
  cpu {
    cores = 4
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.ubuntu_noble.id
    interface    = "scsi0"
    size         = 64
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  initialization {
    datastore_id      = "local-lvm"
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
    ip_config {
      ipv4 {
        address = local.ipv4_address
        gateway = local.ipv4_gateway
      }
    }
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  operating_system {
    type = "l26"
  }
  serial_device {}
  vga {
    type = "serial0"
  }
}

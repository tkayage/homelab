locals {
  node_name    = "proxmox"
  vm_id        = 121
  vm_name      = "services-01"
  ipv4_address = "10.10.30.101/24"
  ipv4_gateway = "10.10.30.1"
  dns_name     = "services.app.kayage.co"
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
  # This base cloud image is shared with the k3s module and is typically
  # already present on the datastore. Adopt the existing (checksum-pinned)
  # file instead of erroring, while still downloading on a fresh host.
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = local.node_name

  source_raw {
    file_name = "services-01-cloud-init.yaml"
    data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      hostname       = local.vm_name
      dns_name       = local.dns_name
      ssh_public_key = var.ssh_public_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "services" {
  name            = local.vm_name
  description     = "Shared services Compose VM managed by OpenTofu"
  tags            = ["opentofu", "services", "durable"]
  node_name       = local.node_name
  vm_id           = local.vm_id
  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  agent {
    enabled = true
  }
  startup {
    order      = "20"
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

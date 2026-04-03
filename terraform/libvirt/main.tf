# Libvirt provider >= 0.9 — nested attributes use `=` object assignment (not blocks).

locals {
  vol_client_name = "${var.project_name}-client.qcow2"
  vol_server_name = "${var.project_name}-server.qcow2"
}

locals {
  ssh_public_key   = trimspace(file(pathexpand(var.ssh_key_file)))
  client_user_data = <<-EOT
#cloud-config
users:
  - name: ${var.libvirt_ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - ${local.ssh_public_key}
hostname: ${var.project_name}-client
manage_etc_hosts: true
EOT
  server_user_data = <<-EOT
#cloud-config
users:
  - name: ${var.libvirt_ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - ${local.ssh_public_key}
hostname: ${var.project_name}-server
manage_etc_hosts: true
EOT
}

resource "libvirt_cloudinit_disk" "client" {
  name      = "${var.project_name}-client-init.iso"
  user_data = local.client_user_data
  meta_data = <<-EOT
instance-id: ${var.project_name}-client
local-hostname: ${var.project_name}-client
EOT
}

resource "libvirt_cloudinit_disk" "server" {
  name      = "${var.project_name}-server-init.iso"
  user_data = local.server_user_data
  meta_data = <<-EOT
instance-id: ${var.project_name}-server
local-hostname: ${var.project_name}-server
EOT
}

resource "libvirt_volume" "client_volume" {
  name = "${var.project_name}-client-volume.qcow2"
  pool = var.pool_name
  capacity = var.disk_size_gib * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }    

  backing_store = {
    path   = "${var.base_volume_path}"
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_domain" "client" {
  name   = "${var.project_name}-client"
  type   = "kvm"
  memory = var.client_memory_mib * 1024
  vcpu   = var.client_vcpu

  os = {
    type = "hvm"
  }
  cpu = {
    mode   = "host-model"
    check  = "partial"
  }

  devices = {
    disks = [
      {
        device = "disk"
        driver = {
          name = "qemu"
          type = libvirt_volume.client_volume.target.format.type
        }
        source = {
          volume = {
            pool   = var.pool_name
            volume = libvirt_volume.client_volume.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_cloudinit_disk.client.path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]
    interfaces = [
      {
        source = {
          network = {
            network = var.network_name
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]
    graphics = [
      {
        spice = {
          listen = "none"
        }
      }
    ]
  }
}

resource "libvirt_volume" "server_volume" {
  name = "${var.project_name}-server-volume.qcow2"
  pool = var.pool_name
  capacity = var.disk_size_gib * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }    

  backing_store = {
    path   = "${var.base_volume_path}"
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_domain" "server" {
  name   = "${var.project_name}-server"
  type   = "kvm"
  memory = var.server_memory_mib * 1024
  vcpu   = var.server_vcpu

  os = {
    type = "hvm"
  }

  cpu = {
    mode  = "host-model"
    check = "partial"
  }

  devices = {
    disks = [
      {
        device = "disk"
        driver = {
          name = "qemu"
          type = libvirt_volume.server_volume.target.format.type
        }
        source = {
          volume = {
            pool   = var.pool_name
            volume = libvirt_volume.server_volume.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_cloudinit_disk.server.path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]
    interfaces = [
      {
        source = {
          network = {
            network = var.network_name
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]
    graphics = [
      {
        spice = {
          listen = "none"
        }
      }
    ]
  }
}

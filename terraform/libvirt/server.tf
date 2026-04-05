# Benchmark server VM (HAProxy + nginx under test).

locals {
  server_user_data = templatefile("${path.module}/templates/cloudinit-server.yaml.tftpl", {
    libvirt_ssh_user      = var.qatbench_libvirt_ssh_user
    ssh_public_key        = local.ssh_public_key
    bench_server_hostname = var.qatbench_server_hostname
    bench_domain          = var.qatbench_domain
  })
}

resource "libvirt_cloudinit_disk" "server" {
  name      = "${var.qatbench_project_name}-server-init.iso"
  user_data = local.server_user_data
  meta_data = templatefile("${path.module}/templates/meta-server.yaml.tftpl", {
    project_name          = var.qatbench_project_name
    bench_server_hostname = var.qatbench_server_hostname
  })
}

resource "libvirt_volume" "server_volume" {
  name     = "${var.qatbench_project_name}-server-volume.qcow2"
  pool     = var.qatbench_libvirt_pool_name
  capacity = var.qatbench_libvirt_disk_size_gib * 1024 * 1024 * 1024
  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = "${var.qatbench_libvirt_base_volume_path}"
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_domain" "server" {
  name      = "${var.qatbench_project_name}-server"
  type      = "kvm"
  memory    = var.qatbench_libvirt_server_memory_mib * 1024
  vcpu      = var.qatbench_libvirt_server_vcpu
  running   = true
  autostart = true

  os = {
    type = "hvm"
  }

  cpu = {
    mode  = "host-model"
    check = "full"
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
            pool   = var.qatbench_libvirt_pool_name
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
        mac = {
          address = var.qatbench_libvirt_server_mac
        }
        source = {
          network = {
            network = libvirt_network.bench.name
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

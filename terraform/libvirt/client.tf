# Benchmark client VM (load generator).

locals {
  # External .tftpl files so terraform-ls resolves var.* in templatefile() args.
  client_user_data = templatefile("${path.module}/templates/cloudinit-client.yaml.tftpl", {
    libvirt_ssh_user      = var.qatbench_libvirt_ssh_user
    ssh_public_key        = local.ssh_public_key
    bench_client_hostname = var.qatbench_client_hostname
    bench_domain          = var.qatbench_domain
  })
}

resource "libvirt_cloudinit_disk" "client" {
  name      = "${var.qatbench_project_name}-client-init.iso"
  user_data = local.client_user_data
  meta_data = templatefile("${path.module}/templates/meta-client.yaml.tftpl", {
    project_name          = var.qatbench_project_name
    bench_client_hostname = var.qatbench_client_hostname
  })
}

resource "libvirt_volume" "client_volume" {
  name     = "${var.qatbench_project_name}-client-volume.qcow2"
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

resource "libvirt_domain" "client" {
  name      = "${var.qatbench_project_name}-client"
  type      = "kvm"
  memory    = var.qatbench_libvirt_client_memory_mib * 1024
  vcpu      = var.qatbench_libvirt_client_vcpu
  running   = true
  autostart = true

  os = {
    type = "hvm"
  }
  cpu = {
    mode = "host-model"
    # Libvirt normalizes running domains to "full"; "partial" causes provider diff after start.
    check = "full"
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
            pool   = var.qatbench_libvirt_pool_name
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
        mac = {
          address = var.qatbench_libvirt_client_mac
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

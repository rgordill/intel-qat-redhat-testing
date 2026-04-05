# NAT network for benchmark VMs: CIDR from var.qatbench_libvirt_network_cidr (sync with ansible qatbench_libvirt_network_cidr).
# Gateway is .1; static DHCP for server (.10) and client (.11); dynamic pool .128–.253.

locals {
  libvirt_net_prefix     = tonumber(split("/", var.qatbench_libvirt_network_cidr)[1])
  libvirt_net_gateway    = cidrhost(var.qatbench_libvirt_network_cidr, 1)
  libvirt_net_server_ip  = cidrhost(var.qatbench_libvirt_network_cidr, 10)
  libvirt_net_client_ip  = cidrhost(var.qatbench_libvirt_network_cidr, 11)
  libvirt_net_dhcp_start = cidrhost(var.qatbench_libvirt_network_cidr, 128)
  libvirt_net_dhcp_end   = cidrhost(var.qatbench_libvirt_network_cidr, 253)
}

resource "libvirt_network" "bench" {
  name      = "${var.qatbench_project_name}-net"
  autostart = true

  domain = {
    name = var.qatbench_domain
  }

  forward = {
    mode = "nat"
  }

  ips = [
    {
      family  = "ipv4"
      address = local.libvirt_net_gateway
      prefix  = local.libvirt_net_prefix
      dhcp = {
        ranges = [
          {
            start = local.libvirt_net_dhcp_start
            end   = local.libvirt_net_dhcp_end
          }
        ]
        hosts = [
          {
            mac  = var.qatbench_libvirt_server_mac
            ip   = local.libvirt_net_server_ip
            name = var.qatbench_server_hostname
          },
          {
            mac  = var.qatbench_libvirt_client_mac
            ip   = local.libvirt_net_client_ip
            name = var.qatbench_client_hostname
          }
        ]
      }
    }
  ]
}

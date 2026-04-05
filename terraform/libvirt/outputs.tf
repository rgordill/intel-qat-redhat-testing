output "client_name" {
  value = libvirt_domain.client.name
}

output "server_name" {
  value = libvirt_domain.server.name
}

output "client_uuid" {
  value = libvirt_domain.client.uuid
}

output "server_uuid" {
  value = libvirt_domain.server.uuid
}

output "ssh_user" {
  value = "cloud-user"
}

output "bench_domain" {
  value       = var.qatbench_domain
  description = "DNS suffix for guest FQDNs (see qatbench_*_hostname variables)"
}

output "client_fqdn" {
  value       = "${var.qatbench_client_hostname}.${var.qatbench_domain}"
  description = "FQDN inside the client guest (cloud-init)"
}

output "server_fqdn" {
  value       = "${var.qatbench_server_hostname}.${var.qatbench_domain}"
  description = "FQDN inside the server guest (cloud-init)"
}

output "libvirt_network_name" {
  value       = libvirt_network.bench.name
  description = "Libvirt network for benchmark VMs (NAT; CIDR from qatbench_libvirt_network_cidr)"
}

output "libvirt_network_cidr" {
  value       = var.qatbench_libvirt_network_cidr
  description = "IPv4 CIDR of the benchmark NAT network"
}

output "client_ip" {
  value       = local.libvirt_net_client_ip
  description = "Reserved DHCP IPv4 for client (cidrhost + 11)"
}

output "server_ip" {
  value       = local.libvirt_net_server_ip
  description = "Reserved DHCP IPv4 for server (cidrhost + 10)"
}

output "ip_discovery_hint" {
  description = "Reserved addresses match DHCP; confirm with virsh domifaddr after boot if needed."
  value       = "virsh domifaddr <name>"
}

output "ansible_inventory_snippet" {
  value = <<-EOT
[client]
${libvirt_domain.client.name} ansible_user=cloud-user ansible_host=${local.libvirt_net_client_ip}

[server]
${libvirt_domain.server.name} ansible_user=cloud-user ansible_host=${local.libvirt_net_server_ip}
EOT
}

output "ansible_inventory_yaml" {
  description = "Full Ansible inventory YAML from tfstate (reserved DHCP IPs). Write: scripts/terraform/render-ansible-inventory.sh libvirt"
  value       = <<-EOT
---
# Generated from terraform output ansible_inventory_yaml (libvirt). Do not commit generated file (see .gitignore).
all:
  vars:
    provider: libvirt
    qatbench_vm_domain: ${var.qatbench_domain}
    qatbench_client_fqdn: ${var.qatbench_client_hostname}.${var.qatbench_domain}
    qatbench_server_fqdn: ${var.qatbench_server_hostname}.${var.qatbench_domain}
  children:
    client:
      hosts:
        bench-client:
          ansible_host: ${local.libvirt_net_client_ip}
          ansible_user: ${var.qatbench_libvirt_ssh_user}
    server:
      hosts:
        bench-server:
          ansible_host: ${local.libvirt_net_server_ip}
          ansible_user: ${var.qatbench_libvirt_ssh_user}
EOT
}

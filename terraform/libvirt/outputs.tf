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

output "ip_discovery_hint" {
  description = "Provider 0.9 does not export guest IPs; use virsh after boot."
  value       = "virsh domifaddr <name>"
}

output "ansible_inventory_snippet" {
  value = <<-EOT
[client]
${libvirt_domain.client.name} ansible_user=cloud-user ansible_host=<CLIENT_IP>

[server]
${libvirt_domain.server.name} ansible_user=cloud-user ansible_host=<SERVER_IP>
EOT
}

output "client_public_ip" {
  value = aws_instance.client.public_ip
}

output "client_private_ip" {
  value = aws_instance.client.private_ip
}

output "server_public_ip" {
  value = aws_instance.server.public_ip
}

output "server_private_ip" {
  value = aws_instance.server.private_ip
}

output "ssh_user" {
  value = "ec2-user"
}

output "bench_domain" {
  value       = var.qatbench_domain
  description = "Ansible: qatbench_aws_domain"
}

output "client_fqdn" {
  value       = "${var.qatbench_client_hostname}.${var.qatbench_domain}"
  description = "Ansible: qatbench_aws_client_fqdn"
}

output "server_fqdn" {
  value       = "${var.qatbench_server_hostname}.${var.qatbench_domain}"
  description = "Ansible: qatbench_aws_server_fqdn"
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "route53_private_zone_id" {
  description = "Private hosted zone for qatbench_domain (in-VPC DNS; replaces BIND on libvirt)."
  value       = aws_route53_zone.bench_private.zone_id
}

locals {
  # Single source for scripts/terraform/render-ansible-inventory.sh (public IPs from state).
  ansible_inventory_yaml = <<-EOT
---
# Generated from terraform output ansible_inventory_yaml (AWS). Do not commit generated file (see .gitignore).
# Use inventory keys bench-client / bench-server. DNS: Route53 private zone (network.tf), not BIND.
all:
  vars:
    provider: aws
    qatbench_vm_domain: ${var.qatbench_domain}
    qatbench_aws_domain: ${var.qatbench_domain}
    qatbench_aws_client_fqdn: ${var.qatbench_client_hostname}.${var.qatbench_domain}
    qatbench_aws_server_fqdn: ${var.qatbench_server_hostname}.${var.qatbench_domain}
  children:
    client:
      hosts:
        bench-client:
          ansible_host: ${aws_instance.client.public_ip}
          ansible_user: ec2-user
    server:
      hosts:
        bench-server:
          ansible_host: ${aws_instance.server.public_ip}
          ansible_user: ec2-user
EOT
}

output "ansible_inventory_yaml" {
  description = "Full Ansible inventory YAML from tfstate (EC2 public IPs). Write: scripts/terraform/render-ansible-inventory.sh aws"
  value       = local.ansible_inventory_yaml
}

output "ansible_inventory_snippet" {
  description = "Alias of ansible_inventory_yaml (backward compatibility)."
  value       = local.ansible_inventory_yaml
}

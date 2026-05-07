output "client_public_ip" {
  value       = aws_eip.client.public_ip
  description = "Elastic IP on primary ENI (public subnet)"
}

output "client_private_ip" {
  value       = aws_network_interface.client_private.private_ip
  description = "Secondary ENI in private subnet (in-VPC benchmark traffic)"
}

output "server_public_ip" {
  value       = aws_eip.server.public_ip
  description = "Elastic IP on primary ENI (public subnet)"
}

output "server_private_ip" {
  value       = aws_network_interface.server_private.private_ip
  description = "Secondary ENI in private subnet (HAProxy / *.apps targets)"
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

output "route53_public_zone_id" {
  description = "Public hosted zone used for bench-client, bench-server (EIPs), and *.apps (server private ENI)."
  value       = data.aws_route53_zone.public.zone_id
}

locals {
  ansible_inventory_yaml = <<-EOT
---
# Generated from terraform output ansible_inventory_yaml (AWS). Do not commit generated file (see .gitignore).
# SSH uses Elastic IPs (primary ENI). DNS: public Route53 zone (network.tf).
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
          ansible_host: ${aws_eip.client.public_ip}
          ansible_user: ec2-user
    server:
      hosts:
        bench-server:
          ansible_host: ${aws_eip.server.public_ip}
          ansible_user: ec2-user
EOT
}

output "ansible_inventory_yaml" {
  description = "Full Ansible inventory YAML from tfstate (Elastic IPs for SSH from outside the VPC)."
  value       = local.ansible_inventory_yaml
}

output "ansible_inventory_snippet" {
  description = "Alias of ansible_inventory_yaml (backward compatibility)."
  value       = local.ansible_inventory_yaml
}

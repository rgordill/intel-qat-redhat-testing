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

output "vpc_id" {
  value = aws_vpc.this.id
}

output "ansible_inventory_snippet" {
  value = <<-EOT
[client]
${aws_instance.client.public_ip} ansible_user=ec2-user ansible_host=${aws_instance.client.public_ip}

[server]
${aws_instance.server.public_ip} ansible_user=ec2-user ansible_host=${aws_instance.server.public_ip}
EOT
}

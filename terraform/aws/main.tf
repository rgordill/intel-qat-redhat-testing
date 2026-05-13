data "aws_ami" "rhel9" {
  count       = var.qatbench_aws_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["309956199498"] # Red Hat (verify for your account/subscription)

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*-Hourly2-GP3"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami            = var.qatbench_aws_ami_id != "" ? var.qatbench_aws_ami_id : data.aws_ami.rhel9[0].id
  ssh_public_key = trimspace(file(pathexpand(var.qatbench_ssh_key_file)))
  # Match ansible qatbench_aws_* (group_vars); cloud-init sets guest hostname/FQDN for bench scripts.
  client_user_data = <<-EOT
#cloud-config
hostname: ${var.qatbench_client_hostname}
fqdn: ${var.qatbench_client_hostname}.${var.qatbench_domain}
manage_etc_hosts: true
EOT
  server_user_data = <<-EOT
#cloud-config
hostname: ${var.qatbench_server_hostname}
fqdn: ${var.qatbench_server_hostname}.${var.qatbench_domain}
manage_etc_hosts: true
EOT
}

resource "aws_key_pair" "bench" {
  key_name   = "${var.qatbench_project_name}-key"
  public_key = local.ssh_public_key
}

resource "aws_instance" "client" {
  ami           = local.ami
  instance_type = var.qatbench_aws_client_instance_type
  key_name      = aws_key_pair.bench.key_name
  user_data     = local.client_user_data

  network_interface {
    network_interface_id = aws_network_interface.client_public.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.client_private.id
    device_index         = 1
  }

  root_block_device {
    volume_size = var.qatbench_aws_root_volume_size_gib
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.qatbench_project_name}-client"
    Role = "client"
  }
}

resource "aws_ec2_instance_state" "client_stopped" {
  instance_id = aws_instance.client.id
  state       = "stopped"
}

resource "aws_instance" "server" {
  ami           = local.ami
  instance_type = var.qatbench_aws_server_instance_type
  key_name      = aws_key_pair.bench.key_name
  user_data     = local.server_user_data

  network_interface {
    network_interface_id = aws_network_interface.server_public.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.server_private.id
    device_index         = 1
  }

  root_block_device {
    volume_size = var.qatbench_aws_root_volume_size_gib
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.qatbench_project_name}-server"
    Role = "server"
  }
}

resource "aws_ec2_instance_state" "server_stopped" {
  instance_id = aws_instance.server.id
  state       = "stopped"
}

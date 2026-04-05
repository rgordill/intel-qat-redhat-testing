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

resource "aws_vpc" "this" {
  cidr_block           = var.qatbench_aws_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.qatbench_project_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.qatbench_project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.qatbench_aws_public_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.qatbench_project_name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.qatbench_project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "bench" {
  name        = "${var.qatbench_project_name}-bench"
  description = "qat bench client/server"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP HAProxy"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.qatbench_aws_vpc_cidr]
  }

  ingress {
    description = "HTTPS HAProxy"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.qatbench_aws_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.qatbench_project_name}-bench-sg"
  }
}

resource "aws_key_pair" "bench" {
  key_name   = "${var.qatbench_project_name}-key"
  public_key = local.ssh_public_key
}

resource "aws_instance" "client" {
  ami                    = local.ami
  instance_type          = var.qatbench_aws_client_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  key_name               = aws_key_pair.bench.key_name
  user_data              = local.client_user_data

  root_block_device {
    volume_size = var.qatbench_aws_root_volume_size_gib
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.qatbench_project_name}-client"
    Role = "client"
  }
}

resource "aws_instance" "server" {
  ami                    = local.ami
  instance_type          = var.qatbench_aws_server_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  key_name               = aws_key_pair.bench.key_name
  user_data              = local.server_user_data

  root_block_device {
    volume_size = var.qatbench_aws_root_volume_size_gib
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.qatbench_project_name}-server"
    Role = "server"
  }
}

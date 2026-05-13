# -----------------------------------------------------------------------------
# Network: VPC, subnets, routing, NAT, security group, ENIs, Elastic IPs, DNS
# -----------------------------------------------------------------------------

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
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.qatbench_project_name}-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.qatbench_aws_private_subnet_cidr
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.qatbench_project_name}-private"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${var.qatbench_project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.qatbench_project_name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.qatbench_project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bench" {
  name        = "${var.qatbench_project_name}-bench"
  description = "qat bench client/server: SSH from internet; bench traffic within VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from internet (primary ENI: public subnet + Elastic IP)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Prometheus scrape: HAProxy exporter/stats on TCP/1936 (server)"
    from_port   = 8405
    to_port     = 8405
    protocol    = "tcp"
    cidr_blocks = var.qatbench_aws_prometheus_exporter_cidr_blocks
  }

  ingress {
    description = "TCP within VPC (client to server for load tests, HAProxy, etc.)"
    from_port   = 1
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.qatbench_aws_vpc_cidr]
  }

  ingress {
    description = "ICMP within VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
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

# Primary: public subnet + Elastic IP (EC2 shows public IPv4; SSH / public DNS). Secondary: private subnet (east-west test traffic).
resource "aws_network_interface" "client_private" {
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.bench.id]

  tags = {
    Name = "${var.qatbench_project_name}-client-private"
  }
}

resource "aws_network_interface" "client_public" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.bench.id]

  tags = {
    Name = "${var.qatbench_project_name}-client-public"
  }
}

resource "aws_network_interface" "server_private" {
  subnet_id       = aws_subnet.private.id
  security_groups = [aws_security_group.bench.id]

  tags = {
    Name = "${var.qatbench_project_name}-server-private"
  }
}

resource "aws_network_interface" "server_public" {
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.bench.id]

  tags = {
    Name = "${var.qatbench_project_name}-server-public"
  }
}

resource "aws_eip" "client" {
  domain = "vpc"
  tags = {
    Name = "${var.qatbench_project_name}-client-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip" "server" {
  domain = "vpc"
  tags = {
    Name = "${var.qatbench_project_name}-server-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_eip_association" "client" {
  allocation_id        = aws_eip.client.id
  network_interface_id = aws_network_interface.client_public.id
}

resource "aws_eip_association" "server" {
  allocation_id        = aws_eip.server.id
  network_interface_id = aws_network_interface.server_public.id
}

# Public hosted zone must already exist. bench-client / bench-server → Elastic IPs;
# *.apps.<domain> → server private-subnet ENI (in-VPC apps traffic).

data "aws_route53_zone" "public" {
  zone_id      = var.qatbench_route53_public_zone_id != "" ? var.qatbench_route53_public_zone_id : null
  name         = var.qatbench_route53_public_zone_id == "" ? var.qatbench_domain : null
  private_zone = false
}

resource "aws_route53_record" "bench_client" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "${var.qatbench_client_hostname}.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.client.public_ip]
}

resource "aws_route53_record" "bench_server" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "${var.qatbench_server_hostname}.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.server.public_ip]
}

resource "aws_route53_record" "bench_apps_wildcard" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = "*.apps.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_network_interface.server_private.private_ip]
}

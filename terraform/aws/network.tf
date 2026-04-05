# Private Route53 zone attached to the benchmark VPC (in-VPC DNS).
# Replaces BIND (bind_server / bind_client_resolver) used on libvirt.
# Resolves bench-client.<domain>, bench-server.<domain>, and *.apps.<domain> (HAProxy) to instance private IPs.

resource "aws_route53_zone" "bench_private" {
  name = var.qatbench_domain

  vpc {
    vpc_id = aws_vpc.this.id
  }

  tags = {
    Name = "${var.qatbench_project_name}-private-dns"
  }
}

resource "aws_route53_record" "bench_client" {
  zone_id = aws_route53_zone.bench_private.zone_id
  name    = "${var.qatbench_client_hostname}.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.client.private_ip]
}

resource "aws_route53_record" "bench_server" {
  zone_id = aws_route53_zone.bench_private.zone_id
  name    = "${var.qatbench_server_hostname}.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.server.private_ip]
}

# OpenShift-style ingress: all *.apps.<domain> → HAProxy on the server instance.
resource "aws_route53_record" "bench_apps_wildcard" {
  zone_id = aws_route53_zone.bench_private.zone_id
  name    = "*.apps.${var.qatbench_domain}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.server.private_ip]
}

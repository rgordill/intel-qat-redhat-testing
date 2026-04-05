# AWS benchmark stack. Naming: qatbench_aws_* for AWS-only; qatbench_* for shared benchmark inputs.

variable "qatbench_aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "qatbench_project_name" {
  type    = string
  default = "qat-bench"
}

variable "qatbench_domain" {
  type        = string
  description = "DNS suffix for EC2 guest FQDNs; keep in sync with ansible qatbench_aws_domain when using AWS inventory"
  default     = "aws-bench.demo"
}

variable "qatbench_client_hostname" {
  type        = string
  description = "Short hostname in the client instance (inventory host key: bench-client)"
  default     = "bench-client"
}

variable "qatbench_server_hostname" {
  type        = string
  description = "Short hostname in the server instance (inventory host key: bench-server)"
  default     = "bench-server"
}

variable "qatbench_aws_vpc_cidr" {
  type    = string
  default = "10.47.0.0/16"
}

variable "qatbench_aws_public_subnet_cidr" {
  type    = string
  default = "10.47.1.0/24"
}

variable "qatbench_ssh_key_file" {
  type        = string
  description = "Path to SSH public key file for aws_key_pair (ec2-user login)"
  default     = "~/.ssh/id_rsa.pub"
}

variable "qatbench_aws_client_instance_type" {
  type        = string
  description = "e.g. c7i.large (smoke) or c7i.metal-24xl (QAT)"
  default     = "c7i.large"
}

variable "qatbench_aws_server_instance_type" {
  type    = string
  default = "c7i.large"
}

variable "qatbench_aws_ami_id" {
  type        = string
  description = "RHEL 9 x86_64 HVM AMI for the region; set explicitly or via data source in main"
  default     = ""
}

variable "qatbench_aws_root_volume_size_gib" {
  type    = number
  default = 30
}

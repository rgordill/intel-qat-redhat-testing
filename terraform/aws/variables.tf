variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "project_name" {
  type    = string
  default = "qat-bench"
}

variable "vpc_cidr" {
  type    = string
  default = "10.47.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.47.1.0/24"
}

variable "ssh_key_file" {
  type        = string
  description = "Path to SSH public key file for aws_key_pair (ec2-user login)"
  default     = "~/.ssh/id_rsa.pub"
}

variable "client_instance_type" {
  type        = string
  description = "e.g. c7i.large (smoke) or c7i.metal-24xl (QAT)"
  default     = "c7i.large"
}

variable "server_instance_type" {
  type    = string
  default = "c7i.large"
}

variable "ami_id" {
  type        = string
  description = "RHEL 9 x86_64 HVM AMI for the region; set explicitly or via data source in main"
  default     = ""
}

variable "root_volume_size_gib" {
  type    = number
  default = 30
}

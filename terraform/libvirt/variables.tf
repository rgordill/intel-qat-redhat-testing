# Shared libvirt / cloud-init inputs (see variables-client.tf and variables-server.tf for per-VM settings).
# Naming: common benchmark inputs use qatbench_*; libvirt-only use qatbench_libvirt_*.

variable "qatbench_libvirt_uri" {
  type        = string
  description = "Libvirt connection URI (e.g. qemu:///system)"
  default     = "qemu:///system"
}

variable "qatbench_project_name" {
  type        = string
  description = "Prefix for resource names"
  default     = "qatbench"
}

variable "qatbench_domain" {
  type        = string
  description = "DNS suffix for benchmark VMs (guest hostname FQDN; e.g. atik.demo). Match group_vars libvirt.network.domain."
  default     = "atik.demo"
}

variable "qatbench_libvirt_pool_name" {
  type        = string
  description = "Libvirt storage pool name"
  default     = "default"
}

variable "qatbench_libvirt_base_volume_path" {
  type        = string
  description = "Path to the base volume in the pool"
  default     = "/var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2"
}

variable "qatbench_ssh_key_file" {
  type        = string
  description = "Path on the machine running Terraform to the SSH public key file (authorized for qatbench_libvirt_ssh_user / cloud-init)"
  default     = "~/.ssh/id_rsa.pub"
}

variable "qatbench_libvirt_ssh_user" {
  type        = string
  description = "Cloud-init user that receives ssh_authorized_keys (RHEL KVM cloud image: cloud-user)"
  default     = "cloud-user"
}

variable "qatbench_libvirt_network_cidr" {
  type        = string
  description = "IPv4 CIDR for the dedicated libvirt NAT network (gateway .1; DHCP static: server .10, client .11; pool .128–.253). Match ansible qatbench_libvirt_network_cidr."
  default     = "192.168.152.0/24"
}

variable "qatbench_libvirt_disk_size_gib" {
  type        = number
  description = "Per-VM overlay disk size (GiB)"
  default     = 10
}

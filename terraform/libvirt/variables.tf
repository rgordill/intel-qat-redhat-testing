variable "libvirt_uri" {
  type        = string
  description = "Libvirt connection URI (e.g. qemu:///system)"
  default     = "qemu:///system"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names"
  default     = "qat-bench"
}

variable "pool_name" {
  type        = string
  description = "Libvirt storage pool name"
  default     = "default"
}

variable "base_volume_path" {
  type        = string
  description = "Path to the base volume in the pool"
  default     = "/var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2"
}

variable "ssh_key_file" {
  type        = string
  description = "Path on the machine running Terraform to the SSH public key file (authorized for libvirt_ssh_user / cloud-init)"
  default     = "~/.ssh/id_rsa.pub"
}

variable "libvirt_ssh_user" {
  type        = string
  description = "Cloud-init user that receives ssh_authorized_keys (RHEL KVM cloud image: cloud-user)"
  default     = "cloud-user"
}

variable "network_name" {
  type        = string
  description = "Libvirt network for guest NICs"
  default     = "default"
}

variable "client_vcpu" {
  type    = number
  default = 2
}

variable "client_memory_mib" {
  type    = number
  default = 4096
}

variable "server_vcpu" {
  type    = number
  default = 2
}

variable "server_memory_mib" {
  type    = number
  default = 4096
}

variable "disk_size_gib" {
  type        = number
  description = "Per-VM overlay disk size (GiB)"
  default     = 10
}

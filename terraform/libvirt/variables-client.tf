# Client benchmark VM (load generator).

variable "qatbench_client_hostname" {
  type        = string
  description = "Short hostname inside the client guest (must match ansible inventory host short name)"
  default     = "bench-client"
}

variable "qatbench_libvirt_client_vcpu" {
  type    = number
  default = 2
}

variable "qatbench_libvirt_client_memory_mib" {
  type    = number
  default = 4096
}

variable "qatbench_libvirt_client_mac" {
  type        = string
  description = "MAC address for the client VM NIC (must match DHCP host entry). Match ansible qatbench_libvirt_client_mac."
  default     = "52:54:00:ab:cd:01"
}


# Server benchmark VM (HAProxy + nginx under test).

variable "qatbench_server_hostname" {
  type        = string
  description = "Short hostname inside the server guest (must match ansible inventory host short name)"
  default     = "bench-server"
}

variable "qatbench_libvirt_server_vcpu" {
  type    = number
  default = 2
}

variable "qatbench_libvirt_server_memory_mib" {
  type    = number
  default = 4096
}

variable "qatbench_libvirt_server_mac" {
  type        = string
  description = "MAC address for the server VM NIC (must match DHCP host entry). Match ansible qatbench_libvirt_server_mac."
  default     = "52:54:00:ab:cd:02"
}


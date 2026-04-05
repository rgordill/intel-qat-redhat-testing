# Libvirt provider >= 0.9 — nested attributes use `=` object assignment (not blocks).
# NAT network: network.tf. Client VM: client.tf. Server VM: server.tf.

locals {
  ssh_public_key = trimspace(file(pathexpand(var.qatbench_ssh_key_file)))
}

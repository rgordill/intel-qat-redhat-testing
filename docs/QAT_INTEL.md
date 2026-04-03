# Intel QAT on bare metal (`c7i.metal-24xl`)

After **Gate A** (AWS `c7i.large` smoke), resize to **`c7i.metal-24xl`** and follow:

- [Running in a Virtual Machine (VM)](https://intel.github.io/quickassist/qatlib/running_in_vm.html) — guest/kernel/VFIO items apply where you use passthrough; on **native metal** use QATlib install docs for driver binding.
- Run the same **standalone** checks Intel documents for Docker on the **RHEL host** (see plan: `lspci`, `qatmgr`, engine/sample).

Ansible role `qat_prereqs` installs `qatlib` by default; extend `qatbench_packages` in `host_vars` for your OpenSSL/QAT engine packages.

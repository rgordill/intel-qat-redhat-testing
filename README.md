# Intel QAT + HAProxy benchmark (project qat)

Implements the staged plan: **libvirt (laptop)** → **AWS c7i.large** → **AWS c7i.metal-24xl** with optional **OpenShift Ingress** examples.

## Layout

| Path | Purpose |
|------|---------|
| `terraform/libvirt/` | KVM guests (2 vCPU / 4 GiB / 10 GiB, RHEL 9.6 qcow2 base) |
| `terraform/aws/` | VPC + two instances (types via variables) |
| `ansible/` | Roles: certs, nginx, `haproxy_server`, optional `haproxy_qat_build` (USE_ENGINE SRPM rebuild when `enable_qat`), QAT prereqs, load client, `terraform` (libvirt or AWS via `provider` in `group_vars` / `-e provider=`) |
| `docs/` | `ROUTER_ENV_MAPPING.md`, `PHASE2_ROUTER_EXTRACTION.md`, `HAPROXY_USE_ENGINE_BUILD.md` (RHEL AppStream SRPM + `USE_ENGINE=1`), gate log template |
| `scripts/utils/` | `wrk-cps-smoke.sh`, `gates.sh`, `render-haproxy-env.sh`, `wrk-latency-report.lua` |
| `scripts/vm/` | **`provision-infrastructure.sh`** *libvirt* or *aws* (Terraform + inventory), **`deploy_components.sh`** (Ansible `deploy_benchmark.yml` once), **`run-scenarios.sh`** (CSV-driven client smoke tests over SSH; **`--list`** prints the table), plus `deploy-scenario.sh`, thin wrappers `deploy-and-test-all.sh` / `libvirt-provision-and-deploy.sh` |
| `scripts/vm/scenarios.csv` | Per-row **id** (unique), topology, **target_url**, **wrk_run** / **wrk_threads** / **wrk_connections** / **wrk_duration_sec** |
| `scripts/vm/scenarios.md` | Markdown table generated from the CSV — run **`scripts/vm/render-scenarios-md.sh`** after editing the CSV |
| `scripts/vm/result.csv` / **`result.md`** | Wrk run results from **`run-scenarios.sh`**; refresh **`result.md`** with **`scripts/vm/render-results-md.sh`** |
| `scripts/terraform/` | `render-ansible-inventory.sh` — writes `inventory/hosts.auto.yml` from `terraform output ansible_inventory_yaml` (libvirt or AWS state) |
| `scripts/vm/generate-scenarios.sh` | Optional: expand `scenarios.template.yaml` into `scenarios.csv` (wrk grid: CPU/thread and connection multipliers); needs `pip install -r scripts/vm/requirements-generate-scenarios.txt` |
| `scripts/vm/inventory_from_ansible.py` | Uses **`ansible-inventory --list`** (same merged vars as playbooks) for server IP / `qatbench_server_fqdn` — used by `run-scenarios.sh` |
| `scripts/openshift/` | Same for `kubectl` + `kubernetes/` manifests (`INGRESS_HOST` required) |
| `kubernetes/` | Example nginx + Ingress (HTTP / edge / reencrypt) for OCP |

## Prerequisites

- Terraform >= 1.5, `terraform-provider-libvirt` (libvirt **qemu:///system**)
- Ansible + collections (pinned in `ansible/requirements.yml`, includes `ansible.posix`, `community.general`):  
  `ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections`
- Optional quality gate: from `ansible/`, run `ansible-lint playbooks roles` (uses `ansible/.ansible-lint`)
- RHEL KVM image at `/var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2` (or override variable)
- SSH **public** key path: `ansible/group_vars/all.yml` sets `qatbench_ssh_key_file` (default `~/.ssh/id_rsa.pub`); no Vault required for that. Optional vault only for other secrets (`vault.yml.template`).

## Libvirt

Uses **terraform-provider-libvirt** `>= 0.9` (nested `devices` / volume `backing_store`). A dedicated NAT network is created from `qatbench_libvirt_network_cidr` in `ansible/group_vars/all.yml` (gateway `.1`, DHCP static server `.10` / client `.11`, MACs `qatbench_libvirt_*_mac`). Outputs `client_ip` / `server_ip` match those reservations; confirm with `virsh domifaddr <name>` if needed.

```bash
cd terraform/libvirt
terraform init
cp terraform.tfvars.example terraform.tfvars   # optional: qatbench_ssh_key_file, qatbench_libvirt_*, network CIDR/MACs
terraform apply
cd ../..
./scripts/terraform/render-ansible-inventory.sh libvirt   # writes ansible/inventory/hosts.auto.yml from state
cd ansible
ansible-playbook playbooks/terraform.yml
ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml
```

Re-run the benchmark stack: `ansible-playbook -i inventory/… playbooks/deploy_benchmark.yml` (see `docs/ROUTER_ENV_MAPPING.md`).

## AWS

```bash
cd terraform/aws
terraform init
cp terraform.tfvars.example terraform.tfvars
export AWS_PROFILE=…
terraform apply
cd ../..
./scripts/terraform/render-ansible-inventory.sh aws   # writes ansible/inventory/hosts.auto.yml from state
cd ansible
ansible-playbook playbooks/terraform.yml -e provider=aws
ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml
```

## Gates and load tests

- Use `docs/gate-log-template.md` before promoting stages.
- CPS smoke: `scripts/utils/wrk-cps-smoke.sh http://SERVER:80/ 5` (install wrk on client via Ansible role).
- **VM (libvirt/AWS):** `./scripts/vm/provision-infrastructure.sh libvirt` or `… aws`, then `./scripts/vm/deploy_components.sh`, then `./scripts/vm/run-scenarios.sh` (or `--list` for the CSV table). Optional `SERVER=<ip>` overrides `openssl s_client -connect` only; ping uses the hostname from each scenario `target_url`. Low-level: `./scripts/vm/deploy-scenario.sh c` (Ansible only).

## OpenShift

```bash
INGRESS_HOST=qat-bench.apps.<cluster>.example.com ./scripts/openshift/deploy-scenario.sh a
# or all scenarios:
INGRESS_HOST=… ./scripts/openshift/deploy-and-test-all.sh
```

Base manifests live under `kubernetes/`; scripts substitute `INGRESS_HOST` into Ingress `host` fields. Edit TLS secrets and `ingressClassName` for your cluster.

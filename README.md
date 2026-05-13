# Intel QAT + HAProxy benchmark (project qatbench)

Reproducible TLS benchmark for **HAProxy on RHEL 9** with optional **Intel QAT** hardware offload via OpenSSL `qatengine`. Staged deployment: **libvirt (laptop/lab)** → **AWS c7i.large** → **AWS c7i.metal-24xl** (bare-metal for QAT), with optional **OpenShift Ingress** examples.

Two VMs are provisioned per environment — a **server** (HAProxy + nginx backend) and a **client** (wrk load generator). Terraform creates all resources in a **stopped state**; VMs are started explicitly before deploying the benchmark stack.

## Layout

| Path | Purpose |
|------|---------|
| `terraform/libvirt/` | KVM guests (RHEL 9.6 qcow2 overlay, NAT network with static DHCP) |
| `terraform/aws/` | VPC, dual-ENI EC2 instances, Elastic IPs, Route53 DNS, security groups |
| `ansible/` | Roles for the full benchmark stack (certs, nginx, HAProxy, QAT prereqs, observability, load client) |
| `ansible/group_vars/` | Shared (`all.yml`) and per-group (`server.yml`, `client.yml`) variables; `vault.yml.template` for secrets |
| `docs/` | Engineering notes: QAT build, observability findings, router extraction |
| `scripts/vm/` | VM workflow: provision, deploy, run CSV-driven scenarios, render results |
| `scripts/terraform/` | Inventory rendering from Terraform state, graph helper |
| `scripts/openshift/` | OpenShift/Kubernetes scenario deployment and testing |
| `kubernetes/` | Example nginx + Ingress manifests (HTTP, edge TLS, reencrypt) for OCP |

## Prerequisites

- **Terraform** >= 1.5
- **Libvirt provider**: `terraform-provider-libvirt` >= 0.9 (for `qemu:///system`)
- **Ansible** + collections (pinned in `ansible/requirements.yml`):
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections
  ```
- **Libvirt**: RHEL 9.6 KVM image at `/var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2` (override via `qatbench_libvirt_base_volume_path`)
- **AWS**: valid credentials (`AWS_PROFILE` or environment), a public Route53 hosted zone matching `qatbench_domain`
- **SSH public key**: path set in `ansible/group_vars/all.yml` → `libvirt.ssh.key_file` (default `~/.ssh/id_rsa.pub`)
- **RHEL subscription** (optional): copy `ansible/group_vars/vault.yml.template` → `vault.yml`, fill in `vault_rhel_org_id` / `vault_rhel_activation_key`, encrypt with `ansible-vault encrypt ansible/group_vars/vault.yml`
- **Linting** (optional): `cd ansible && ansible-lint playbooks roles` (config in `.ansible-lint`)

## Infrastructure: created stopped

Both providers create VMs in a **stopped** state so Terraform apply is safe to run without incurring runtime costs or triggering cloud-init prematurely.

| Provider | Mechanism | Start method |
|----------|-----------|--------------|
| **Libvirt** | `running = false`, `autostart = false` on `libvirt_domain` | `provision-infrastructure.sh libvirt` runs `virsh start`; or manual `virsh start <domain>` |
| **AWS** | `aws_ec2_instance_state` resources set `state = "stopped"` after creation | Start via AWS Console, CLI (`aws ec2 start-instances`), or change the state resource to `"running"` |

The libvirt **NAT network** is created with `autostart = true` so it persists across host reboots.

## Libvirt quickstart

```bash
cd terraform/libvirt
terraform init
cp terraform.tfvars.example terraform.tfvars   # adjust SSH key, base image path, network CIDR/MACs
terraform apply                                 # creates VMs stopped
cd ../..

# Provision: starts VMs, waits for DHCP, renders Ansible inventory
./scripts/vm/provision-infrastructure.sh libvirt

# Deploy benchmark stack
./scripts/vm/deploy_components.sh

# Run scenarios
./scripts/vm/run-scenarios.sh --list            # print scenario table
./scripts/vm/run-scenarios.sh                   # run all scenarios
./scripts/vm/run-scenarios.sh a c               # run specific scenario IDs
```

The libvirt network uses a dedicated NAT range from `qatbench_libvirt_network_cidr` (default `192.168.152.0/24`): gateway `.1`, server `.10`, client `.11`, dynamic pool `.128–.253`. MAC-based static DHCP reservations ensure stable IPs.

## AWS quickstart

```bash
cd terraform/aws
terraform init
cp terraform.tfvars.example terraform.tfvars   # set domain, region, SSH key, instance types
export AWS_PROFILE=…
terraform apply                                 # creates instances stopped
cd ../..

# Render inventory from Terraform state
./scripts/terraform/render-ansible-inventory.sh aws

# Start instances (Terraform leaves them stopped)
aws ec2 start-instances --instance-ids <client-id> <server-id>

# Deploy benchmark stack
./scripts/vm/deploy_components.sh

# Run scenarios
./scripts/vm/run-scenarios.sh --list
./scripts/vm/run-scenarios.sh
```

AWS networking: each instance has two ENIs — a **public** ENI with Elastic IP (SSH access) and a **private** ENI in a separate subnet (in-VPC benchmark traffic). Route53 creates `bench-client`/`bench-server` A records pointing to Elastic IPs and `*.apps.<domain>` pointing to the server's private ENI.

## Ansible roles

Roles are applied via `ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml`.

### Server roles (applied in order)

| Role | Description |
|------|-------------|
| `rhel_subscription` | RHSM registration with activation key (when `rhel_subscription_enabled: true`) |
| `bind_server` | BIND authoritative DNS for benchmark domain (libvirt only) |
| `certs` | OpenSSL CA + nginx cert + HAProxy wildcard cert for `*.apps.<domain>` |
| `nginx_server_backend` | Minimal nginx serving static responses as HAProxy backend |
| `qat_prereqs` | Kernel cmdline (IOMMU, vfio-pci), QAT packages, VFIO udev rules, `qat.service` (when `enable_qat: true`) |
| `haproxy_qat_build` | SRPM rebuild of HAProxy with `USE_ENGINE=1` for QAT offload (when `enable_qat: true`) |
| `haproxy_server` | HAProxy install, gomplate-rendered config with `ROUTER_*` env map, TLS frontends, systemd overrides for QAT |
| `qatbench_observability` | Installs perf, bpftrace, socat; deploys snapshot script for runtime data collection |

### Client roles

| Role | Description |
|------|-------------|
| `rhel_subscription` | RHSM registration (when enabled) |
| `bind_client_resolver` | Point client DNS at server's BIND (libvirt only) |
| `loadtest_client` | Pull CA from server, update trust store, install wrk from EPEL/Copr |

## Scenarios

Benchmark scenarios are defined in `scripts/vm/scenarios.csv`. Each row specifies:

| Column | Description |
|--------|-------------|
| `id` | Unique scenario identifier |
| `topology` | Deployment topology description |
| `target_url` | URL to test (supports Jinja2 variables from Ansible inventory) |
| `wrk_run` | Whether to run wrk load test (`1`/`0`) |
| `wrk_threads` | wrk thread count |
| `wrk_connections` | wrk connection count |
| `wrk_duration_sec` | wrk test duration in seconds |

Scripts:
- `run-scenarios.sh --list` — print the scenario table
- `run-scenarios.sh [ids...]` — run scenarios (ping → openssl → curl → wrk) via SSH to the client
- `render-scenarios-md.sh` — regenerate `scenarios.md` from CSV
- `render-results-md.sh` — regenerate `result.md` from `result.csv`
- `generate-scenarios.sh` — expand `scenarios.template.yaml` into a CSV grid (requires `pip install -r requirements-generate-scenarios.txt`)

Results are written to `scripts/vm/result.csv` (gitignored) with columns for wrk metrics (requests/sec, latency, transfer rate, socket errors).

## Observability

The `qatbench_observability` role installs tooling on the server and deploys a snapshot script that collects:
- OpenSSL engine status and QAT/VFIO device state
- HAProxy socket stats and Prometheus metrics (port 8405)
- Optional `perf record` and bpftrace profiling

Collect snapshots from the controller:
```bash
ansible-playbook -i inventory/hosts.auto.yml playbooks/collect_observability.yml
```
Artifacts are fetched to `ansible/artifacts/qatbench_observability/` (tarballs gitignored).

The AWS security group allows TCP 8405 inbound from `qatbench_aws_prometheus_exporter_cidr_blocks` (default `0.0.0.0/0`) for external Prometheus scraping.

## OpenShift

```bash
INGRESS_HOST=qat-bench.apps.<cluster>.example.com ./scripts/openshift/deploy-scenario.sh a
# or all scenarios:
INGRESS_HOST=… ./scripts/openshift/deploy-and-test-all.sh
```

Base manifests in `kubernetes/` include nginx Deployment, Service, and Ingress examples (HTTP, edge TLS, reencrypt). Scripts substitute `INGRESS_HOST` into Ingress `host` fields.

## Key configuration files

| File | Purpose |
|------|---------|
| `ansible/group_vars/all.yml` | Provider selection, libvirt/AWS settings, project name, QAT toggle, cert dir |
| `ansible/group_vars/server.yml` | Per-provider server specs (vCPU, memory, instance type — auto-selects `c7i.metal-24xl` when `enable_qat`) |
| `ansible/group_vars/client.yml` | Per-provider client specs |
| `ansible/group_vars/vault.yml.template` | Template for RHSM secrets (copy to `vault.yml` and encrypt) |
| `terraform/libvirt/terraform.tfvars.example` | Libvirt overrides (SSH key, base image, network CIDR, MACs) |
| `terraform/aws/terraform.tfvars.example` | AWS overrides (region, domain, Route53, instance types, Prometheus CIDRs) |
| `scripts/vm/scenarios.csv` | Benchmark scenario definitions |

## Documentation

| File | Topic |
|------|-------|
| `docs/HAPROXY_QAT_ENGINE_OVERVIEW.md` | End-to-end QAT + HAProxy architecture and role ordering |
| `docs/HAPROXY_USE_ENGINE_BUILD.md` | Manual SRPM rebuild with `USE_ENGINE=1` |
| `docs/QAT_INTEL.md` | Intel QAT hardware requirements and references |
| `docs/QAT_TLS_OBSERVABILITY_FINDINGS.md` | Observability artifacts and collection workflow |
| `docs/PHASE2_ROUTER_EXTRACTION.md` | Extracting live OpenShift router config for parity checks |

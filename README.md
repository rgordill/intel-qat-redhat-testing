# Intel QAT + HAProxy benchmark (project qat)

Implements the staged plan: **libvirt (laptop)** → **AWS c7i.large** → **AWS c7i.metal-24xl** with optional **OpenShift Ingress** examples.

## Layout

| Path | Purpose |
|------|---------|
| `terraform/libvirt/` | KVM guests (2 vCPU / 4 GiB / 10 GiB, RHEL 9.6 qcow2 base) |
| `terraform/aws/` | VPC + two instances (types via variables) |
| `ansible/` | Roles: certs, nginx, haproxy, optional QAT prereqs, load client, Terraform wrappers |
| `docs/` | `ROUTER_ENV_MAPPING.md`, `PHASE2_ROUTER_EXTRACTION.md`, gate log template |
| `scripts/utils/` | `wrk-cps-smoke.sh`, `gates.sh`, `render-haproxy-env.sh`, `wrk-latency-report.lua` |
| `scripts/vm/` | `deploy-scenario.sh`, `run-scenario-tests.sh`, `deploy-and-test-all.sh` (Ansible `haproxy_scenario` a–e) |
| `scripts/openshift/` | Same for `kubectl` + `kubernetes/` manifests (`INGRESS_HOST` required) |
| `kubernetes/` | Example nginx + Ingress (HTTP / edge / reencrypt) for OCP |

## Prerequisites

- Terraform >= 1.5, `terraform-provider-libvirt` (libvirt **qemu:///system**)
- Ansible + collections (pinned in `ansible/requirements.yml`):  
  `ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections`
- Optional quality gate: from `ansible/`, run `ansible-lint playbooks roles` (uses `ansible/.ansible-lint`)
- RHEL KVM image at `/var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2` (or override variable)
- SSH **public** key path: `ansible/group_vars/all.yml` sets `ssh_key_file` (default `~/.ssh/id_rsa.pub`); no Vault required for that. Optional vault only for other secrets (`vault.yml.template`).

## Libvirt

Uses **terraform-provider-libvirt** `>= 0.9` (nested `devices` / volume `backing_store`). After `apply`, discover IPs with `virsh domifaddr <name>` — Terraform does not export guest IPv4.

```bash
cd terraform/libvirt
terraform init
cp terraform.tfvars.example terraform.tfvars   # optional: ssh_key_file, libvirt_ssh_user
terraform apply
# Set ansible_host in ansible/inventory/hosts.yml (virsh domifaddr …)
cd ../../ansible
ansible-playbook playbooks/terraform_libvirt.yml
ansible-playbook -i inventory/hosts.yml playbooks/deploy_benchmark.yml
```

Switch HAProxy scenario: set `haproxy_scenario: b` (a–e) in `ansible/group_vars/all.yml`, re-run `deploy_benchmark.yml`, or use `scripts/vm/deploy-scenario.sh b` (passes `-e haproxy_scenario=b` via Ansible).

## AWS

```bash
cd terraform/aws
terraform init
cp terraform.tfvars.example terraform.tfvars
export AWS_PROFILE=…
terraform apply
```

Update `ansible/inventory/hosts.yml` to `ec2-user` and public IPs from outputs; run `playbooks/terraform_aws.yml` (optional) and `deploy_benchmark.yml`.

## Gates and load tests

- Use `docs/gate-log-template.md` before promoting stages.
- CPS smoke: `scripts/utils/wrk-cps-smoke.sh http://SERVER:80/ 5` (install wrk on client via Ansible role).
- **VM (libvirt/AWS):** `SERVER=<haproxy-ip> ./scripts/vm/deploy-and-test-all.sh` or `./scripts/vm/deploy-scenario.sh c` then `./scripts/vm/run-scenario-tests.sh c --server <ip>`.

## OpenShift

```bash
INGRESS_HOST=qat-bench.apps.<cluster>.example.com ./scripts/openshift/deploy-scenario.sh a
# or all scenarios:
INGRESS_HOST=… ./scripts/openshift/deploy-and-test-all.sh
```

Base manifests live under `kubernetes/`; scripts substitute `INGRESS_HOST` into Ingress `host` fields. Edit TLS secrets and `ingressClassName` for your cluster.

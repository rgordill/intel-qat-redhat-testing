#!/usr/bin/env bash
# Deploy benchmark server and client (Ansible playbooks/deploy_benchmark.yml).
# Run once (or after changes) before ./run-scenarios.sh.
#
# Inventory: QAT_BENCH_INVENTORY, or QAT_BENCH_PROVIDER / group_vars/all.yml provider
# (same resolution as run-scenarios.sh).
#
# Usage:
#   ./deploy_components.sh
#   ./deploy_components.sh -h
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  sed -n '1,20p' "$0"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

export QAT_BENCH_INVENTORY="${QAT_BENCH_INVENTORY:-$(resolved_inventory_path)}"
INV_ABS="${QAT_BENCH_ROOT}/ansible/${QAT_BENCH_INVENTORY}"
if [[ ! -f "$INV_ABS" ]]; then
  echo "ERROR: inventory not found: ${INV_ABS} (run ./scripts/terraform/render-ansible-inventory.sh libvirt|aws, or provision-infrastructure.sh, or set QAT_BENCH_INVENTORY)" >&2
  exit 1
fi

cd "${QAT_BENCH_ROOT}/ansible"
export ANSIBLE_CONFIG="${QAT_BENCH_ROOT}/ansible/ansible.cfg"

echo "[deploy-components] ansible-playbook -i ${QAT_BENCH_INVENTORY} playbooks/deploy_benchmark.yml"
ansible-playbook -i "${QAT_BENCH_INVENTORY}" playbooks/deploy_benchmark.yml

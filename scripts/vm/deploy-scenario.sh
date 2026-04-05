#!/usr/bin/env bash
# Deploy one HAProxy scenario (a–e) via Ansible on the benchmark server.
# Run from anywhere; uses ansible/inventory/hosts.yml and ansible/ansible.cfg.
#
# Usage:
#   ./deploy-scenario.sh <a|b|c|d|e> [extra ansible-playbook args]
# Example:
#   ./deploy-scenario.sh b
#   ./deploy-scenario.sh e -e qatbench_enable_qat=true
#   ./deploy-scenario.sh b --ask-vault-pass   # only if playbooks use vault for other secrets
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  sed -n '1,20p' "$0"
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi

sc=$(scenario_lower "${1:?scenario a–e required}")
shift || true
if ! valid_scenario "$sc"; then
  echo "Invalid scenario: use a|b|c|d|e" >&2
  exit 1
fi

cd "${QAT_BENCH_ROOT}/ansible"
export ANSIBLE_CONFIG="${QAT_BENCH_ROOT}/ansible/ansible.cfg"
exec ansible-playbook -i "${QAT_BENCH_INVENTORY}" playbooks/deploy_benchmark.yml \
  -e "haproxy_scenario=${sc}" "$@"

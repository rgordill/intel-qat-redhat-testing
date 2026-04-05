#!/usr/bin/env bash
# Write ansible/inventory/*.auto.yml from Terraform state (terraform output -raw ansible_inventory_yaml).
# Requires: terraform >= 1.x, initialized stack with outputs (apply or refresh at least once).
#
# Usage:
#   ./render-ansible-inventory.sh libvirt
#   ./render-ansible-inventory.sh aws
# Env:
#   QAT_BENCH_ROOT  Repo root (default: inferred from script path)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
QAT_BENCH_ROOT="${QAT_BENCH_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

usage() {
  sed -n '1,20p' "$0"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

PROVIDER="${1:?Usage: $0 libvirt|aws}"
TF_DIR="${QAT_BENCH_ROOT}/terraform/${PROVIDER}"

case "$PROVIDER" in
  libvirt)
    OUT="${QAT_BENCH_ROOT}/ansible/inventory/hosts.auto.yml"
    ;;
  aws)
    OUT="${QAT_BENCH_ROOT}/ansible/inventory/hosts.aws.auto.yml"
    ;;
  *)
    echo "Unknown provider: ${PROVIDER} (use libvirt or aws)" >&2
    exit 1
    ;;
esac

if [[ ! -d "$TF_DIR" ]]; then
  echo "ERROR: ${TF_DIR} not found" >&2
  exit 1
fi

cd "$TF_DIR"
terraform init -input=false

if ! terraform output -raw ansible_inventory_yaml >"${OUT}.tmp"; then
  echo "ERROR: terraform output ansible_inventory_yaml failed in ${TF_DIR}." >&2
  echo "Apply or refresh the stack so outputs exist (see terraform/${PROVIDER}/)." >&2
  rm -f "${OUT}.tmp"
  exit 1
fi

mv "${OUT}.tmp" "$OUT"
echo "Wrote ${OUT}"
echo "Example: cd ${QAT_BENCH_ROOT}/ansible && ansible-playbook -i inventory/$(basename "$OUT") playbooks/deploy_benchmark.yml"
echo "Or: export QAT_BENCH_INVENTORY=inventory/$(basename "$OUT")   # for scripts/vm/*.sh"

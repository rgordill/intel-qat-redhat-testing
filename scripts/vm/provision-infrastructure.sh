#!/usr/bin/env bash
# Provision benchmark client + server VMs with Terraform (libvirt or AWS), render Ansible inventory.
# Does not deploy HAProxy scenarios or run tests — use run-scenarios.sh for that.
#
# Prerequisites: Terraform, provider plugins, Ansible + collections (see ansible/requirements.yml).
# Libvirt: qemu:///system, base qcow2 path in group_vars / terraform variables.
# AWS: credentials and region (aws.region in group_vars).
#
# Usage:
#   ./provision-infrastructure.sh <libvirt|aws>
#   SKIP_TERRAFORM=1 ./provision-infrastructure.sh libvirt   # refresh inventory only (terraform outputs must exist)
#
# After success, exports (print):
#   QAT_BENCH_PROVIDER, QAT_BENCH_INVENTORY — source your shell or copy into CI.
#
# Env:
#   SKIP_TERRAFORM=1     Skip terraform apply (reuse existing state; still renders inventory)
#   LIBVIRT_WAIT_SECS=300   Libvirt: max wait for guest NIC addresses (virsh domifaddr)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  sed -n '1,35p' "$0"
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi

PROVIDER=$(scenario_lower "${1:?Usage: $0 <libvirt|aws>}")
case "$PROVIDER" in
  libvirt|aws) ;;
  *)
    echo "Invalid provider: ${PROVIDER} (use libvirt or aws)" >&2
    exit 1
    ;;
esac

TF_DIR="${QAT_BENCH_ROOT}/terraform/${PROVIDER}"
LIBVIRT_WAIT_SECS="${LIBVIRT_WAIT_SECS:-300}"

libvirt_guest_ipv4() {
  local dom=$1
  virsh domifaddr "$dom" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}

ensure_domain_running() {
  local dom=$1
  local st
  st=$(virsh domstate "$dom" 2>/dev/null | tr -d '\r' || echo "")
  if [[ -z "$st" ]]; then
    echo "[libvirt] ERROR: domain not found: ${dom}" >&2
    return 1
  fi
  case "$st" in
    running) ;;
    "shut off")
      echo "[libvirt] starting ${dom} (was shut off)"
      virsh start "$dom"
      ;;
    paused)
      echo "[libvirt] resuming ${dom}"
      virsh resume "$dom"
      ;;
    *)
      echo "[libvirt] WARN: ${dom} unexpected state: ${st}" >&2
      ;;
  esac
}

wait_libvirt_ssh_addrs() {
  local client_dom=$1 server_dom=$2 client_ip=$3 server_ip=$4
  local deadline=$((SECONDS + LIBVIRT_WAIT_SECS))
  echo "[libvirt] waiting for guests (${client_ip} / ${server_ip}) on ${client_dom} / ${server_dom} (max ${LIBVIRT_WAIT_SECS}s)..."
  while (( SECONDS < deadline )); do
    local got_c got_s
    got_c=$(libvirt_guest_ipv4 "$client_dom")
    got_s=$(libvirt_guest_ipv4 "$server_dom")
    if [[ "$got_c" == "$client_ip" && "$got_s" == "$server_ip" ]]; then
      return 0
    fi
    sleep 5
  done
  got_c=$(libvirt_guest_ipv4 "$client_dom")
  got_s=$(libvirt_guest_ipv4 "$server_dom")
  echo "[libvirt] WARN: expected client=${client_ip} server=${server_ip}; got client=${got_c:-empty} server=${got_s:-empty}" >&2
}

if [[ "${SKIP_TERRAFORM:-0}" != "1" ]]; then
  echo "[${PROVIDER}] terraform apply via Ansible (playbooks/terraform.yml)"
  (
    cd "${QAT_BENCH_ROOT}/ansible"
    export ANSIBLE_CONFIG="${QAT_BENCH_ROOT}/ansible/ansible.cfg"
    ansible-playbook playbooks/terraform.yml -e "provider=${PROVIDER}"
  )
else
  echo "[${PROVIDER}] SKIP_TERRAFORM=1 — skipping terraform apply"
fi

echo "[${PROVIDER}] render ansible inventory"
"${QAT_BENCH_ROOT}/scripts/terraform/render-ansible-inventory.sh" "$PROVIDER"

INV_REL=$(default_inventory_for_provider "$PROVIDER")
export QAT_BENCH_INVENTORY="$INV_REL"
export QAT_BENCH_PROVIDER="$PROVIDER"

if [[ "$PROVIDER" == "libvirt" ]]; then
  cd "$TF_DIR"
  CLIENT_DOM=$(terraform output -raw client_name)
  SERVER_DOM=$(terraform output -raw server_name)
  CLIENT_IP=$(terraform output -raw client_ip)
  SERVER_IP=$(terraform output -raw server_ip)
  cd "${QAT_BENCH_ROOT}"
  ensure_domain_running "$CLIENT_DOM"
  ensure_domain_running "$SERVER_DOM"
  wait_libvirt_ssh_addrs "$CLIENT_DOM" "$SERVER_DOM" "$CLIENT_IP" "$SERVER_IP" || true
  echo "[libvirt] client ${CLIENT_DOM} -> ${CLIENT_IP}"
  echo "[libvirt] server ${SERVER_DOM} -> ${SERVER_IP}"
fi

if [[ "$PROVIDER" == "aws" ]]; then
  echo "[aws] Route53 private zone and A records are in terraform/aws/network.tf; use in-VPC DNS for FQDNs."
fi

echo ""
echo "Export for follow-up commands:"
echo "  export QAT_BENCH_PROVIDER=${QAT_BENCH_PROVIDER}"
echo "  export QAT_BENCH_INVENTORY=${QAT_BENCH_INVENTORY}"
echo ""
echo "Next: cd ${QAT_BENCH_ROOT}/ansible && ansible-playbook -i \${QAT_BENCH_INVENTORY} playbooks/deploy_benchmark.yml"
echo "Or:   ${SCRIPT_DIR}/run-scenarios.sh --list"
echo "      ${SCRIPT_DIR}/run-scenarios.sh [scenario ids]"

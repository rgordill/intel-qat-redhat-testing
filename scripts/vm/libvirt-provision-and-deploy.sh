#!/usr/bin/env bash
# Provision qat-bench client + server VMs with Terraform (libvirt), write ansible/inventory/hosts.auto.yml,
# run deploy-scenario.sh, then run-scenario-tests.sh from this host against the server.
#
# Prerequisites: Terraform >= 1.5, terraform-provider-libvirt, libvirt (qemu:///system), base qcow2 at
# terraform/libvirt variable base_volume_path (default /var/lib/libvirt/images/rhel-9.6-x86_64-kvm.qcow2),
# Ansible + collections (ansible-galaxy collection install -r ansible/requirements.yml -p ansible/collections).
# RHEL guests: enable subscription before dnf (ansible/group_vars/all.yml + vault); see .cursor/rules/rhel.mdc.
#
# Usage:
#   ./libvirt-provision-and-deploy.sh [a|b|c|d|e]
# Env:
#   SKIP_TERRAFORM=1     Skip terraform apply (reuse existing domains; still refreshes IPs + inventory)
#   LIBVIRT_WAIT_SECS=300  Max wait for guest IPv4 from virsh domifaddr
#   QATBENCH_VM_DOMAIN=atik.demo  DNS suffix for bench-server.<domain> / bench-client.<domain> (must match ansible/terraform)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() { sed -n '1,25p' "$0"; }

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi

sc=$(scenario_lower "${1:-a}")
if ! valid_scenario "$sc"; then
  echo "Invalid scenario: use a|b|c|d|e" >&2
  exit 1
fi

TF_DIR="${QAT_BENCH_ROOT}/terraform/libvirt"
LIBVIRT_WAIT_SECS="${LIBVIRT_WAIT_SECS:-300}"
QATBENCH_VM_DOMAIN="${QATBENCH_VM_DOMAIN:-atik.demo}"
SERVER_FQDN="bench-server.${QATBENCH_VM_DOMAIN}"
CLIENT_FQDN="bench-client.${QATBENCH_VM_DOMAIN}"

libvirt_guest_ipv4() {
  local dom=$1
  # Prefer lease table; works once DHCP has assigned an address.
  virsh domifaddr "$dom" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true
}

# Domains are defined without running=true (older state) or after host reboot; ensure they are up.
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

if [[ "${SKIP_TERRAFORM:-0}" != "1" ]]; then
  echo "[libvirt] terraform init + apply in ${TF_DIR}"
  (cd "$TF_DIR" && terraform init -input=false && terraform apply -auto-approve -input=false)
else
  echo "[libvirt] SKIP_TERRAFORM=1 — skipping terraform apply"
fi

cd "$TF_DIR"
CLIENT_DOM=$(terraform output -raw client_name)
SERVER_DOM=$(terraform output -raw server_name)
SSH_USER=$(terraform output -raw ssh_user)
# Reserved DHCP addresses from network.tf (same CIDR as qatbench_libvirt_network_cidr)
CLIENT_IP=$(terraform output -raw client_ip)
SERVER_IP=$(terraform output -raw server_ip)
cd "${QAT_BENCH_ROOT}"

ensure_domain_running "$CLIENT_DOM"
ensure_domain_running "$SERVER_DOM"

deadline=$((SECONDS + LIBVIRT_WAIT_SECS))
echo "[libvirt] waiting for guests to pick up reserved DHCP (${CLIENT_IP} / ${SERVER_IP}) on ${CLIENT_DOM} and ${SERVER_DOM} (max ${LIBVIRT_WAIT_SECS}s)..."
while (( SECONDS < deadline )); do
  got_c=$(libvirt_guest_ipv4 "$CLIENT_DOM")
  got_s=$(libvirt_guest_ipv4 "$SERVER_DOM")
  if [[ "$got_c" == "$CLIENT_IP" && "$got_s" == "$SERVER_IP" ]]; then
    break
  fi
  sleep 5
done
got_c=$(libvirt_guest_ipv4 "$CLIENT_DOM")
got_s=$(libvirt_guest_ipv4 "$SERVER_DOM")
if [[ "$got_c" != "$CLIENT_IP" || "$got_s" != "$SERVER_IP" ]]; then
  echo "[libvirt] WARN: expected client=${CLIENT_IP} server=${SERVER_IP}; got client=${got_c:-empty} server=${got_s:-empty}" >&2
  echo "[libvirt] Using Terraform reserved addresses for inventory anyway (verify: virsh domifaddr ${CLIENT_DOM}; virsh domifaddr ${SERVER_DOM})" >&2
fi

echo "[libvirt] client ${CLIENT_DOM} -> ${CLIENT_IP}"
echo "[libvirt] server ${SERVER_DOM} -> ${SERVER_IP}"

"${QAT_BENCH_ROOT}/scripts/terraform/render-ansible-inventory.sh" libvirt

export QAT_BENCH_INVENTORY="inventory/hosts.auto.yml"
echo "[ansible] QAT_BENCH_INVENTORY=${QAT_BENCH_INVENTORY}"
"${SCRIPT_DIR}/deploy-scenario.sh" "$sc"

echo "[vm-test] from laptop to HAProxy on server ${SERVER_IP} (${SERVER_FQDN}); wrk via client ${SSH_USER}@${CLIENT_IP} (${CLIENT_FQDN})"
echo "[vm-test] Tip: add to this host's /etc/hosts for curl/openssl by name: ${SERVER_IP} ${SERVER_FQDN}"
WRK_SSH="${SSH_USER}@${CLIENT_IP}" \
  "${SCRIPT_DIR}/run-scenario-tests.sh" "$sc" --server "$SERVER_IP" --url-host "$SERVER_FQDN" --client "${SSH_USER}@${CLIENT_IP}"

echo "[libvirt] scenario ${sc} provision + deploy + smoke OK"

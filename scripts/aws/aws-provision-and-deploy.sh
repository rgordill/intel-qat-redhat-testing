#!/usr/bin/env bash
# Provision qat-bench client + server on AWS (terraform/aws), write ansible/inventory/hosts.aws.auto.yml,
# run deploy-scenario.sh, then run-scenario-tests.sh from this host against the server.
#
# Prerequisites: Terraform >= 1.5, AWS credentials, Ansible + collections (see libvirt-provision-and-deploy.sh).
# First apply with cloud-init user_data replaces EC2 instances if you add bench_domain after an older stack.
#
# Usage:
#   ./aws-provision-and-deploy.sh [a|b|c|d|e]
# Env:
#   SKIP_TERRAFORM=1     Skip terraform apply (still refreshes inventory from outputs)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../vm/common.sh
source "${SCRIPT_DIR}/../vm/common.sh"

usage() { sed -n '1,22p' "$0"; }

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi

sc=$(scenario_lower "${1:-a}")
if ! valid_scenario "$sc"; then
  echo "Invalid scenario: use a|b|c|d|e" >&2
  exit 1
fi

TF_DIR="${QAT_BENCH_ROOT}/terraform/aws"

if [[ "${SKIP_TERRAFORM:-0}" != "1" ]]; then
  echo "[aws] terraform init + apply in ${TF_DIR}"
  (cd "$TF_DIR" && terraform init -input=false && terraform apply -auto-approve -input=false)
else
  echo "[aws] SKIP_TERRAFORM=1 — skipping terraform apply"
fi

cd "$TF_DIR"
CLIENT_IP=$(terraform output -raw client_public_ip)
SERVER_IP=$(terraform output -raw server_public_ip)
SSH_USER=$(terraform output -raw ssh_user)
BENCH_DOMAIN=$(terraform output -raw bench_domain)
CLIENT_FQDN=$(terraform output -raw client_fqdn)
SERVER_FQDN=$(terraform output -raw server_fqdn)
cd "${QAT_BENCH_ROOT}"

echo "[aws] client ${CLIENT_IP} (${CLIENT_FQDN})"
echo "[aws] server ${SERVER_IP} (${SERVER_FQDN})"

"${QAT_BENCH_ROOT}/scripts/terraform/render-ansible-inventory.sh" aws

export QAT_BENCH_INVENTORY="inventory/hosts.aws.auto.yml"
echo "[ansible] QAT_BENCH_INVENTORY=${QAT_BENCH_INVENTORY}"
"${QAT_BENCH_ROOT}/scripts/vm/deploy-scenario.sh" "$sc"

echo "[vm-test] from laptop to HAProxy on server ${SERVER_IP} (${SERVER_FQDN}); wrk via client ${SSH_USER}@${CLIENT_IP} (${CLIENT_FQDN})"
echo "[vm-test] Tip: add to this host's /etc/hosts for curl/openssl by name: ${SERVER_IP} ${SERVER_FQDN}"
WRK_SSH="${SSH_USER}@${CLIENT_IP}" \
  "${QAT_BENCH_ROOT}/scripts/vm/run-scenario-tests.sh" "$sc" --server "$SERVER_IP" --url-host "$SERVER_FQDN" --client "${SSH_USER}@${CLIENT_IP}"

echo "[aws] scenario ${sc} provision + deploy + smoke OK"

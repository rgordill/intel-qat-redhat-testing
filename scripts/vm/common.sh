# shellcheck shell=bash
# Shared helpers for libvirt / AWS VM benchmark scripts (sourced by provision-*.sh / run-*.sh).
QAT_BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QAT_BENCH_ROOT
UTIL_DIR="${QAT_BENCH_ROOT}/scripts/utils"
VM_DIR="${QAT_BENCH_ROOT}/scripts/vm"
# If unset, deploy/run scripts resolve via QAT_BENCH_PROVIDER (e.g. inventory/hosts.auto.yml for libvirt).
QAT_BENCH_INVENTORY="${QAT_BENCH_INVENTORY:-}"
export QAT_BENCH_INVENTORY
# libvirt | aws — used to pick default inventory when QAT_BENCH_INVENTORY is unset
QAT_BENCH_PROVIDER="${QAT_BENCH_PROVIDER:-libvirt}"
export QAT_BENCH_PROVIDER

scenario_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Read one field from scenarios.csv (id = row id column).
scenario_csv_get() {
  local csv=$1 id=$2 field=$3
  python3 "${VM_DIR}/scenario_csv.py" get "$csv" "$id" "$field"
}

scenario_id_in_csv() {
  local csv=$1 id=$2
  scenario_csv_get "$csv" "$id" id >/dev/null 2>&1
}

# Provider from ansible/group_vars/all.yml (same default as playbooks when env unset).
ansible_default_provider() {
  local f="${QAT_BENCH_ROOT}/ansible/group_vars/all.yml"
  if [[ -f "$f" ]]; then
    awk '/^provider:/ {gsub(/["\047]/,"",$2); print $2; exit}' "$f"
  fi
}

# Default inventory path under ansible/ for a provider.
default_inventory_for_provider() {
  case "${1:-libvirt}" in
    libvirt) echo "inventory/hosts.auto.yml" ;;
    aws) echo "inventory/hosts.aws.auto.yml" ;;
    *)
      echo "ERROR: unknown provider: $1 (use libvirt or aws)" >&2
      return 1
      ;;
  esac
}

# Resolve inventory file: env QAT_BENCH_INVENTORY, else default for provider (QAT_BENCH_PROVIDER or group_vars all.yml).
resolved_inventory_path() {
  if [[ -n "${QAT_BENCH_INVENTORY:-}" ]]; then
    echo "$QAT_BENCH_INVENTORY"
    return 0
  fi
  local prov="${QAT_BENCH_PROVIDER:-}"
  [[ -n "$prov" ]] || prov="$(ansible_default_provider)"
  default_inventory_for_provider "${prov:-libvirt}"
}

# Fallback: parse inventory file with awk (no ansible-inventory / no merged vars).
_load_benchmark_inventory_awk() {
  local inv_abs=$1
  BENCH_SERVER_IP=$(awk '/^[[:space:]]*bench-server:[[:space:]]*$/ {h=1; next} h && /ansible_host:/ {print $2; exit}' "$inv_abs")
  BENCH_CLIENT_IP=$(awk '/^[[:space:]]*bench-client:[[:space:]]*$/ {h=1; next} h && /ansible_host:/ {print $2; exit}' "$inv_abs")
  BENCH_SERVER_USER=$(awk '/^[[:space:]]*bench-server:[[:space:]]*$/ {h=1; next} h && /ansible_user:/ {print $2; exit}' "$inv_abs")
  BENCH_CLIENT_USER=$(awk '/^[[:space:]]*bench-client:[[:space:]]*$/ {h=1; next} h && /ansible_user:/ {print $2; exit}' "$inv_abs")
  BENCH_VM_DOMAIN=$(awk '/^[[:space:]]*qatbench_vm_domain:/ {gsub(/["\047]/,"",$2); print $2; exit}' "$inv_abs")
  if [[ -z "${BENCH_VM_DOMAIN:-}" ]]; then
    BENCH_VM_DOMAIN=$(awk '/^[[:space:]]*qatbench_aws_domain:/ {gsub(/["\047]/,"",$2); print $2; exit}' "$inv_abs")
  fi
  BENCH_SERVER_FQDN=$(awk '/^[[:space:]]*qatbench_server_fqdn:/ {gsub(/["\047]/,"",$2); print $2; exit}' "$inv_abs")
  BENCH_CLIENT_FQDN=$(awk '/^[[:space:]]*qatbench_client_fqdn:/ {gsub(/["\047]/,"",$2); print $2; exit}' "$inv_abs")
  BENCH_URL_HOST="${BENCH_SERVER_FQDN:-}"
  if [[ -z "${BENCH_URL_HOST:-}" && -n "${BENCH_VM_DOMAIN:-}" ]]; then
    BENCH_URL_HOST="bench-server.${BENCH_VM_DOMAIN}"
  fi
  if [[ -z "${BENCH_URL_HOST:-}" ]]; then
    BENCH_URL_HOST="${BENCH_SERVER_IP:-}"
  fi
  BENCH_PROVIDER=$(awk '/^provider:/ {gsub(/["\047]/,"",$2); print $2; exit}' "${QAT_BENCH_ROOT}/ansible/group_vars/all.yml" 2>/dev/null || true)
  [[ -n "${BENCH_PROVIDER:-}" ]] || BENCH_PROVIDER=libvirt
  export BENCH_SERVER_IP BENCH_CLIENT_IP BENCH_SERVER_USER BENCH_CLIENT_USER BENCH_VM_DOMAIN
  export BENCH_SERVER_FQDN BENCH_CLIENT_FQDN BENCH_URL_HOST BENCH_PROVIDER
}

# Load bench-server / bench-client addresses and URL host from Ansible (ansible-inventory merge = playbooks).
# Sets: BENCH_SERVER_IP, BENCH_CLIENT_IP, BENCH_*_USER, BENCH_VM_DOMAIN, BENCH_*_FQDN, BENCH_URL_HOST
load_benchmark_inventory() {
  local inv_rel inv_abs out
  inv_rel="$(resolved_inventory_path)"
  inv_abs="${QAT_BENCH_ROOT}/ansible/${inv_rel}"
  if [[ ! -f "$inv_abs" ]]; then
    echo "ERROR: inventory not found: ${inv_abs} (run provision-infrastructure.sh or set QAT_BENCH_INVENTORY)" >&2
    return 1
  fi

  if command -v ansible-inventory >/dev/null 2>&1; then
    out="$(QAT_BENCH_ROOT="${QAT_BENCH_ROOT}" python3 "${VM_DIR}/inventory_from_ansible.py" "${inv_rel}" 2>/dev/null)" || out=""
    if [[ -n "${out}" ]]; then
      # shellcheck disable=SC1090
      eval "${out}"
      export BENCH_SERVER_IP BENCH_CLIENT_IP BENCH_SERVER_USER BENCH_CLIENT_USER BENCH_VM_DOMAIN
      export BENCH_SERVER_FQDN BENCH_CLIENT_FQDN BENCH_URL_HOST BENCH_PROVIDER
      return 0
    fi
  fi

  echo "[bench] WARN: using awk inventory parse (install Ansible CLI for full group_vars merge)" >&2
  _load_benchmark_inventory_awk "$inv_abs"
}

# Print scenarios.csv as a fixed-width table (requires column from util-linux).
print_scenarios_table() {
  local csv=${1:-"${VM_DIR}/scenarios.csv"}
  if [[ ! -f "$csv" ]]; then
    echo "ERROR: scenarios file not found: $csv" >&2
    return 1
  fi
  echo "Benchmark scenarios (source: ${csv})"
  echo ""
  if command -v column >/dev/null 2>&1; then
    column -t -s, <"$csv" | sed 's/^/  /'
  else
    sed 's/^/  /' "$csv"
  fi
  echo ""
}

# List scenario ids from CSV (id column).
scenario_ids_from_csv() {
  local csv=${1:-"${VM_DIR}/scenarios.csv"}
  python3 "${VM_DIR}/scenario_csv.py" ids "$csv"
}

# Expand scenarios.csv target_url for a row (<qatbench_vm_domain> → real domain).
scenario_csv_target_url() {
  local csv=$1 id=$2 domain=$3
  local tpl
  tpl=$(scenario_csv_get "$csv" "$id" target_url)
  echo "${tpl//<qatbench_vm_domain>/${domain}}"
}

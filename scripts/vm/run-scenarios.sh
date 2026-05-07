#!/usr/bin/env bash
# Smoke-test benchmark scenarios (CSV-driven). Deploy server/client first: ./deploy_components.sh
# Definitions: scenarios.csv (see scenarios.md).
#
# Each row has a unique id (e.g. a, a-heavy, c … f) in scenarios.csv.
# Default inventory: ansible/inventory/hosts.auto.yml (override with QAT_BENCH_INVENTORY, or QAT_BENCH_PROVIDER + render).
# Tests run on bench-client over SSH: ping → openssl s_client → curl → wrk. URL from CSV target_url
# expanded with merged Ansible vars (Jinja2 {{ … }} like host vars) and legacy <qatbench_vm_domain>.
# Bench CA on client — curl/wrk use default trust (no -k). Requires ansible-inventory + jinja2 for templated URLs.
# SSH: StrictHostKeyChecking=no, UserKnownHostsFile=/dev/null (lab tests only).
# result.csv: timestamp, scenario, url, provider, wrk_run + wrk_threads/wrk_connections/wrk_duration_sec from scenarios.csv, then parsed wrk metrics and status.
#
# Usage:
#   ./run-scenarios.sh --list
#   ./run-scenarios.sh a a-heavy
#   ./render-scenarios-md.sh   # refresh scripts/vm/scenarios.md from CSV
#
# Inventory: QAT_BENCH_INVENTORY if set; else inventory/hosts.auto.yml for QAT_BENCH_PROVIDER or provider in group_vars/all.yml.
#
# Flags:
#   --list, -l          Print scenarios table (CSV as columns)
#   --csv FILE          Scenario CSV (default: scripts/vm/scenarios.csv)
#   --provider, -p      libvirt|aws — override default inventory when QAT_BENCH_INVENTORY unset
#   --skip-tests        Skip client SSH smoke tests (still prints scenario headers)
#
# Tests: bench-client must be reachable via SSH (inventory). Ping uses the hostname from target_url (DNS).
# Optional SERVER= / bench-server IP (CONNECT_ADDR) overrides openssl -connect only; ping never uses the IP.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

RESULT_CSV="${SCRIPT_DIR}/result.csv"

# Quote a CSV field if it contains comma, quote, or newline.
csv_field() {
  local v=${1-}
  if [[ "$v" == *","* ]] || [[ "$v" == *'"'* ]] || [[ "$v" == *$'\n'* ]]; then
    v=${v//\"/\"\"}
    printf '"%s"' "$v"
  else
    printf '%s' "$v"
  fi
}

# Parse bench-client ssh log; print: requests_per_sec transfer_per_sec total_requests actual_sec latency_avg latency_stdev latency_max socket_errors_line status
parse_wrk_from_log() {
  local txt=$1
  local req trans treq tact la ls lm sock st
  req=$(echo "$txt" | grep '^Requests/sec:' | awk '{print $2}' | head -1)
  trans=$(echo "$txt" | grep '^Transfer/sec:' | awk '{print $2}' | head -1)
  treq=$(echo "$txt" | grep -E '[0-9]+ requests in [0-9.]+s' | head -1 | awk '{print $1}')
  tact=$(echo "$txt" | grep -E '[0-9]+ requests in [0-9.]+s' | head -1 | sed -n 's/.* in \([0-9.]*\)s.*/\1/p')
  la=$(echo "$txt" | awk '/^[[:space:]]+Latency[[:space:]]+/ {print $2; exit}')
  ls=$(echo "$txt" | awk '/^[[:space:]]+Latency[[:space:]]+/ {print $3; exit}')
  lm=$(echo "$txt" | awk '/^[[:space:]]+Latency[[:space:]]+/ {print $4; exit}')
  sock=$(echo "$txt" | grep -E '^[[:space:]]*Socket errors:' | head -1 | sed 's/^[[:space:]]*//')
  st=ok
  if echo "$txt" | grep -q 'wrk skipped'; then
    st=skipped_wrk
    req=; trans=; treq=; tact=; la=; ls=; lm=; sock=
  elif echo "$txt" | grep -q 'wrk not installed'; then
    st=wrk_missing
    req=; trans=; treq=; tact=; la=; ls=; lm=; sock=
  elif [[ -z "${req:-}" ]] && echo "$txt" | grep -qE 'wrk ---|\-\-\- wrk'; then
    st=wrk_no_summary
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "${req:-}" "${trans:-}" "${treq:-}" "${tact:-}" "${la:-}" "${ls:-}" "${lm:-}" "${sock:-}" "$st"
}

SCENARIOS_CSV="${VM_DIR}/scenarios.csv"
SKIP_TESTS=0
LIST_ONLY=0

usage() { sed -n '1,26p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -l|--list) LIST_ONLY=1; shift ;;
    --csv) SCENARIOS_CSV="${2:?}"; shift 2 ;;
    -p|--provider) QAT_BENCH_PROVIDER="${2:?}"; export QAT_BENCH_PROVIDER; shift 2 ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    -*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$LIST_ONLY" == "1" ]]; then
  print_scenarios_table "$SCENARIOS_CSV"
  echo "Markdown: ${VM_DIR}/scenarios.md (run: ${SCRIPT_DIR}/render-scenarios-md.sh)"
  exit 0
fi

REQUESTED=("$@")
mapfile -t CSV_IDS < <(scenario_ids_from_csv "$SCENARIOS_CSV")
if [[ ${#REQUESTED[@]} -eq 0 ]]; then
  REQUESTED=("${CSV_IDS[@]}")
fi

RUN_IDS=()
for id in "${REQUESTED[@]}"; do
  id=$(scenario_lower "$id")
  if ! scenario_id_in_csv "$SCENARIOS_CSV" "$id"; then
    echo "Unknown scenario id: ${id} (not in ${SCENARIOS_CSV})" >&2
    exit 1
  fi
  RUN_IDS+=("$id")
done

if [[ ${#RUN_IDS[@]} -eq 0 ]]; then
  echo "No scenarios to run." >&2
  exit 1
fi

print_scenarios_table "$SCENARIOS_CSV"

export QAT_BENCH_INVENTORY="${QAT_BENCH_INVENTORY:-$(resolved_inventory_path)}"
INV_ABS="${QAT_BENCH_ROOT}/ansible/${QAT_BENCH_INVENTORY}"
if [[ ! -f "$INV_ABS" ]]; then
  echo "ERROR: inventory not found: ${INV_ABS} (run ./scripts/terraform/render-ansible-inventory.sh libvirt|aws, or provision-infrastructure.sh, or set QAT_BENCH_INVENTORY)" >&2
  exit 1
fi

load_benchmark_inventory || exit 1
export QAT_BENCH_PROVIDER="${BENCH_PROVIDER:-${QAT_BENCH_PROVIDER:-libvirt}}"

QAT_BENCH_BENCH_SERVER_VARS_JSON=""
cleanup_bench_server_vars_json() {
  if [[ -n "${QAT_BENCH_BENCH_SERVER_VARS_JSON:-}" && -f "${QAT_BENCH_BENCH_SERVER_VARS_JSON}" ]]; then
    rm -f "${QAT_BENCH_BENCH_SERVER_VARS_JSON}"
  fi
}
trap cleanup_bench_server_vars_json EXIT
if command -v ansible-inventory >/dev/null 2>&1; then
  _bench_vars_tmp=$(mktemp)
  if QAT_BENCH_ROOT="${QAT_BENCH_ROOT}" python3 "${SCRIPT_DIR}/inventory_from_ansible.py" "${QAT_BENCH_INVENTORY}" --bench-server-vars-json >"${_bench_vars_tmp}" 2>/dev/null; then
    QAT_BENCH_BENCH_SERVER_VARS_JSON="${_bench_vars_tmp}"
    export QAT_BENCH_BENCH_SERVER_VARS_JSON
  else
    rm -f "${_bench_vars_tmp}"
  fi
fi

SERVER_ADDR=""
WRK_TARGET="${WRK_SSH:-}"
if [[ "$SKIP_TESTS" != "1" ]]; then
  # Optional: TCP address for openssl s_client -connect (default: hostname from target_url). Ping always uses URL host.
  SERVER_ADDR="${SERVER:-${BENCH_SERVER_IP:-}}"
  # target_url may use Jinja2 / FQDN vars only; domain is not always required.
  if [[ -z "$WRK_TARGET" && -n "${BENCH_CLIENT_USER:-}" && -n "${BENCH_CLIENT_IP:-}" ]]; then
    WRK_TARGET="${BENCH_CLIENT_USER}@${BENCH_CLIENT_IP}"
  fi
  [[ -n "${WRK_TARGET}" ]] || {
    echo "ERROR: bench-client SSH target missing (ansible_host/user in inventory, or set WRK_SSH=user@host)" >&2
    exit 1
  }
fi

# Remote script on bench-client (stdin to ssh bash -s).
CLIENT_TESTS=$(cat <<'EOS'
set -euo pipefail
echo "[vm-test:client] remote script started"
URL="${TARGET_URL:?}"
CONNECT_ADDR="${CONNECT_ADDR:-}"

HOST="${URL#*://}"
HOST="${HOST%%/*}"
HOST="${HOST%%:*}"

# openssl TCP connect: optional CONNECT_ADDR (server IP) else URL hostname (same as curl/wrk).
TLS_CONNECT="${CONNECT_ADDR:-$HOST}"

# Plain HTTP scenarios: do not probe :443 with openssl (s_client can hang waiting on TLS).
IS_HTTP_ONLY=0
[[ "${URL}" == http://* ]] && IS_HTTP_ONLY=1

if [[ -n "${HOST}" ]]; then
  echo "[vm-test:client] --- ping -> ${HOST} (URL host) ---"
  if ping -c 1 -W 2 "${HOST}" 2>/dev/null; then
    :
  else
    echo "[vm-test:client] ping failed or blocked (continuing)"
  fi
else
  echo "[vm-test:client] --- ping skipped (no host in URL) ---"
fi

if [[ "${IS_HTTP_ONLY}" == "1" ]]; then
  echo "[vm-test:client] --- openssl skipped (http:// URL — not a TLS hop) ---"
elif [[ -n "${TLS_CONNECT}" ]]; then
  echo "[vm-test:client] --- openssl s_client (SNI=${HOST} -> ${TLS_CONNECT}:443) ---"
  if command -v openssl >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      echo | timeout 8 openssl s_client -connect "${TLS_CONNECT}:443" -servername "${HOST}" -brief 2>/dev/null | head -8 || echo "[vm-test:client] openssl: timeout or no TLS on 443 (non-fatal)"
    else
      echo | openssl s_client -connect "${TLS_CONNECT}:443" -servername "${HOST}" -brief 2>/dev/null | head -8 || echo "[vm-test:client] openssl: no TLS on 443 or connection failed (non-fatal)"
    fi
  else
    echo "[vm-test:client] openssl not installed"
  fi
else
  echo "[vm-test:client] --- openssl skipped (no URL host and no CONNECT_ADDR) ---"
fi

echo "[vm-test:client] --- curl -> ${URL} ---"
curl -sfS -o /dev/null --connect-timeout 5 "${URL}"

if [[ "${SKIP_WRK:-0}" == "1" ]]; then
  echo "[vm-test:client] wrk skipped (SKIP_WRK=1)"
elif [[ "${WRK_RUN_EFFECTIVE:-0}" != "1" ]]; then
  echo "[vm-test:client] wrk skipped (WRK_RUN=${WRK_RUN_EFFECTIVE})"
elif command -v wrk >/dev/null 2>&1; then
  echo "[vm-test:client] --- wrk ---"
  # Pin wrk to as many CPUs as possible, capped by WRK_THREADS.
  cpu_count=""
  if command -v nproc >/dev/null 2>&1; then
    cpu_count="$(nproc --all 2>/dev/null || nproc 2>/dev/null || true)"
  fi
  if [[ -z "${cpu_count}" ]]; then
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  fi
  if [[ -z "${cpu_count}" ]] || ! [[ "${cpu_count}" =~ ^[0-9]+$ ]] || [[ "${cpu_count}" -lt 1 ]]; then
    cpu_count=1
  fi

  wrk_threads="${WRK_THREADS:-1}"
  if [[ -z "${wrk_threads}" ]] || ! [[ "${wrk_threads}" =~ ^[0-9]+$ ]] || [[ "${wrk_threads}" -lt 1 ]]; then
    wrk_threads=1
  fi

  pin_count="${wrk_threads}"
  if [[ "${pin_count}" -gt "${cpu_count}" ]]; then
    pin_count="${cpu_count}"
  fi

  WRK_CMD=(wrk -t"${WRK_THREADS}" -c"${WRK_CONNECTIONS}" -d"${WRK_DURATION}s" --latency
    -H "Connection: close"
    "${URL}"
  )

  if command -v taskset >/dev/null 2>&1; then
    if [[ "${pin_count}" -le 1 ]]; then
      echo "[vm-test:client] wrk cpu pinning: taskset -c 0"
      taskset -c 0 "${WRK_CMD[@]}"
    else
      echo "[vm-test:client] wrk cpu pinning: taskset -c 0-$((pin_count - 1)) (client_cpus=${cpu_count}, wrk_threads=${wrk_threads})"
      taskset -c "0-$((pin_count - 1))" "${WRK_CMD[@]}"
    fi
  else
    echo "[vm-test:client] wrk cpu pinning: taskset not installed (client_cpus=${cpu_count}, wrk_threads=${wrk_threads})"
    "${WRK_CMD[@]}"
  fi
else
  echo "[vm-test:client] wrk not installed on client; install wrk or set SKIP_WRK=1" >&2
  exit 1
fi
EOS
)

cd "${QAT_BENCH_ROOT}/ansible"
export ANSIBLE_CONFIG="${QAT_BENCH_ROOT}/ansible/ansible.cfg"

if [[ "$SKIP_TESTS" != "1" ]]; then
  printf '%s\n' \
    "timestamp_utc,scenario_id,target_url,provider,wrk_run,wrk_threads,wrk_connections,wrk_duration_sec,requests_per_sec,transfer_per_sec,total_requests,wrk_actual_sec,latency_avg_ms,latency_stdev_ms,latency_max_ms,socket_errors,status" \
    >"$RESULT_CSV"
  echo "[run-scenarios] results -> ${RESULT_CSV}"
fi

for rid in "${RUN_IDS[@]}"; do
  wrk_run=$(scenario_csv_get "$SCENARIOS_CSV" "$rid" wrk_run)
  wrk_threads=$(scenario_csv_get "$SCENARIOS_CSV" "$rid" wrk_threads)
  wrk_connections=$(scenario_csv_get "$SCENARIOS_CSV" "$rid" wrk_connections)
  wrk_duration=$(scenario_csv_get "$SCENARIOS_CSV" "$rid" wrk_duration_sec)
  target_url=$(scenario_csv_target_url "$SCENARIOS_CSV" "$rid" "${QAT_BENCH_INVENTORY}")

  wrk_run_effective="${wrk_run}"
  if [[ -z "$wrk_run_effective" ]]; then
    if [[ "${target_url}" == http://* ]]; then wrk_run_effective=1; else wrk_run_effective=0; fi
  fi

  echo ""
  echo "======== scenario id=${rid} provider=${QAT_BENCH_PROVIDER} url=${target_url} wrk_run=${wrk_run_effective} wrk t=${wrk_threads} c=${wrk_connections} d=${wrk_duration}s ========"
  if [[ "$SKIP_TESTS" != "1" ]]; then
    printf '[vm-test] ssh %s scenario=%s url=%s\n' "${WRK_TARGET}" "${rid}" "${target_url}"
    ssh_tmp=$(mktemp)
    ssh_rc=0
    # shellcheck disable=SC2029
    ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o GSSAPIAuthentication=no \
      -o PreferredAuthentications=publickey \
      -o ConnectTimeout=15 \
      "${WRK_TARGET}" \
      env TARGET_URL="${target_url}" \
      CONNECT_ADDR="${SERVER_ADDR}" \
      WRK_RUN_EFFECTIVE="${wrk_run_effective}" \
      WRK_THREADS="${wrk_threads}" WRK_CONNECTIONS="${wrk_connections}" WRK_DURATION="${wrk_duration}" \
      SKIP_WRK="${SKIP_WRK:-0}" \
      bash -s <<<"${CLIENT_TESTS}" >"$ssh_tmp" 2>&1 || ssh_rc=$?
    ssh_text=$(cat "$ssh_tmp")
    cat "$ssh_tmp"
    rm -f "$ssh_tmp"
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    IFS=$'\t' read -r req trans treq tact la ls lm sock st <<< "$(parse_wrk_from_log "$ssh_text")"
    if [[ "$ssh_rc" -ne 0 ]]; then
      st=ssh_failed
    fi
    {
      printf '%s,%s,%s,%s,%s,%s,%s,%s' \
        "$ts" \
        "$(csv_field "$rid")" \
        "$(csv_field "$target_url")" \
        "$QAT_BENCH_PROVIDER" \
        "$wrk_run" \
        "$wrk_threads" \
        "$wrk_connections" \
        "$wrk_duration"
      printf ',%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${req:-}" \
        "${trans:-}" \
        "${treq:-}" \
        "${tact:-}" \
        "${la:-}" \
        "${ls:-}" \
        "${lm:-}" \
        "$(csv_field "${sock:-}")" \
        "$st"
    } >>"$RESULT_CSV"
    printf '[vm-test] done scenario=%s\n' "${rid}"
    if [[ "$ssh_rc" -ne 0 ]]; then
      exit "$ssh_rc"
    fi
  fi
done

echo ""
echo "[run-scenarios] completed: ${RUN_IDS[*]}"
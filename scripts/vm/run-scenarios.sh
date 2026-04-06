#!/usr/bin/env bash
# Deploy and/or smoke-test benchmark scenarios. Definitions: scenarios.csv (see scenarios.md).
#
# Each row has a unique id (e.g. a, a-heavy, c … f) in scenarios.csv.
# Default inventory path follows provider in ansible/group_vars/all.yml (override with QAT_BENCH_INVENTORY or QAT_BENCH_PROVIDER).
# Smoke tests run on bench-client over SSH: ping → openssl s_client → curl → wrk. URL from CSV target_url
# (<qatbench_vm_domain> replaced from inventory). Bench CA on client — curl/wrk use default trust (no -k).
# SSH: StrictHostKeyChecking=no, UserKnownHostsFile=/dev/null (lab tests only).
# result.csv: timestamp, scenario, url, provider, wrk_run + wrk_threads/wrk_connections/wrk_duration_sec from scenarios.csv, then parsed wrk metrics and status.
#
# Usage:
#   ./run-scenarios.sh --list
#   ./run-scenarios.sh a a-heavy
#   ./render-scenarios-md.sh   # refresh scripts/vm/scenarios.md from CSV
#
# Inventory: QAT_BENCH_INVENTORY, or QAT_BENCH_PROVIDER (libvirt|aws), else provider from ansible/group_vars/all.yml.
#
# Flags:
#   --list, -l          Print scenarios table (CSV as columns)
#   --csv FILE          Scenario CSV (default: scripts/vm/scenarios.csv)
#   --provider, -p      libvirt|aws — override default inventory when QAT_BENCH_INVENTORY unset
#   --skip-deploy       Only run smoke tests
#   --skip-tests        Only ansible deploy per row
#
# Tests: bench-client must be reachable via SSH (inventory); SERVER= sets HAProxy IP for ping/openssl (default bench-server).
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
SKIP_DEPLOY=0
SKIP_TESTS=0
LIST_ONLY=0

usage() { sed -n '1,75p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -l|--list) LIST_ONLY=1; shift ;;
    --csv) SCENARIOS_CSV="${2:?}"; shift 2 ;;
    -p|--provider) QAT_BENCH_PROVIDER="${2:?}"; export QAT_BENCH_PROVIDER; shift 2 ;;
    --skip-deploy) SKIP_DEPLOY=1; shift ;;
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
  echo "ERROR: inventory not found: ${INV_ABS} (run provision-infrastructure.sh or set QAT_BENCH_INVENTORY)" >&2
  exit 1
fi

load_benchmark_inventory || exit 1
export QAT_BENCH_PROVIDER="${BENCH_PROVIDER:-${QAT_BENCH_PROVIDER:-libvirt}}"

SERVER_ADDR=""
WRK_TARGET="${WRK_SSH:-}"
if [[ "$SKIP_TESTS" != "1" ]]; then
  SERVER_ADDR="${SERVER:-${BENCH_SERVER_IP:-}}"
  [[ -n "${SERVER_ADDR}" ]] || { echo "ERROR: bench-server ansible_host missing from inventory (or set SERVER)" >&2; exit 1; }
  [[ -n "${BENCH_VM_DOMAIN:-}" ]] || { echo "ERROR: qatbench_vm_domain (or aws domain) missing from inventory — needed for scenarios.csv target_url" >&2; exit 1; }
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
URL="${TARGET_URL:?}"
CONNECT_ADDR="${CONNECT_ADDR:-}"

HOST="${URL#*://}"
HOST="${HOST%%/*}"
HOST="${HOST%%:*}"

if [[ -n "${CONNECT_ADDR}" ]]; then
  echo "[vm-test:client] --- ping -> ${CONNECT_ADDR} ---"
  if ping -c 3 -W 2 "${CONNECT_ADDR}" 2>/dev/null; then
    :
  else
    echo "[vm-test:client] ping failed or blocked (continuing)"
  fi

  echo "[vm-test:client] --- openssl s_client (SNI=${HOST} -> ${CONNECT_ADDR}:443) ---"
  if command -v openssl >/dev/null 2>&1; then
    echo | openssl s_client -connect "${CONNECT_ADDR}:443" -servername "${HOST}" -brief 2>/dev/null | head -8 || echo "[vm-test:client] openssl: no TLS on 443 or connection failed (non-fatal for HTTP-only routes)"
  else
    echo "[vm-test:client] openssl not installed"
  fi
else
  echo "[vm-test:client] --- ping/openssl skipped (no CONNECT_ADDR) ---"
fi

echo "[vm-test:client] --- curl -> ${URL} ---"
curl -sfS -o /dev/null --connect-timeout 5 "${URL}"

if [[ "${SKIP_WRK:-0}" == "1" ]]; then
  echo "[vm-test:client] wrk skipped (SKIP_WRK=1)"
elif [[ "${WRK_RUN_EFFECTIVE:-0}" != "1" ]]; then
  echo "[vm-test:client] wrk skipped (WRK_RUN=${WRK_RUN_EFFECTIVE})"
elif command -v wrk >/dev/null 2>&1; then
  echo "[vm-test:client] --- wrk ---"
  wrk -t"${WRK_THREADS}" -c"${WRK_CONNECTIONS}" -d"${WRK_DURATION}s" --latency \
    -H "Connection: close" \
    "${URL}"
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
  target_url=$(scenario_csv_target_url "$SCENARIOS_CSV" "$rid" "${BENCH_VM_DOMAIN}")

  wrk_run_effective="${wrk_run}"
  if [[ -z "$wrk_run_effective" ]]; then
    if [[ "${target_url}" == http://* ]]; then wrk_run_effective=1; else wrk_run_effective=0; fi
  fi

  echo ""
  echo "======== scenario id=${rid} provider=${QAT_BENCH_PROVIDER} url=${target_url} wrk_run=${wrk_run_effective} wrk t=${wrk_threads} c=${wrk_connections} d=${wrk_duration}s ========"
  if [[ "$SKIP_DEPLOY" != "1" ]]; then
    ansible-playbook -i "${QAT_BENCH_INVENTORY}" playbooks/deploy_benchmark.yml
  fi
  if [[ "$SKIP_TESTS" != "1" ]]; then
    printf '[vm-test] ssh %s scenario=%s url=%s\n' "${WRK_TARGET}" "${rid}" "${target_url}"
    ssh_tmp=$(mktemp)
    ssh_rc=0
    # shellcheck disable=SC2029
    ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
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

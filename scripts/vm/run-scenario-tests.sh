#!/usr/bin/env bash
# Smoke tests for one VM scenario: curl (+ openssl handshake for TLS), optional wrk for (a).
# wrk runs locally if on PATH; otherwise use --client user@host or WRK_SSH to run wrk on the benchmark client VM.
#
# Usage:
#   ./run-scenario-tests.sh <a|b|c|d|e> --server <host|ip> [--url-host <fqdn>] [--client <user@client-host>]
# Examples:
#   ./run-scenario-tests.sh a --server 192.168.122.213
#   ./run-scenario-tests.sh a --server 192.168.122.213 --url-host bench-server.atik.demo
#   ./run-scenario-tests.sh a --server 192.168.122.213 --client cloud-user@192.168.122.139
#   WRK_SSH=cloud-user@192.168.122.139 ./run-scenario-tests.sh a --server 192.168.122.213 --url-host bench-server.atik.demo
# --url-host: Hostname used in HTTP(S) URLs and openssl SNI (e.g. bench-server.atik.demo). Defaults to --server.
#   Use when curl runs from a host without DNS but wrk runs on the client VM (see Ansible /etc/hosts).
# Env:
#   QATBENCH_URL_HOST  Same as --url-host (overridden by CLI)
#   SNI          Server Name for openssl s_client (default: url-host / --server)
#   SKIP_WRK     set to 1 to skip wrk (default runs wrk only for scenario a)
#   WRK_DURATION seconds (default 5)
#   WRK_SSH      user@host — run wrk over ssh when wrk is not installed locally (same as --client)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

log() { printf '[vm-test] %s\n' "$*"; }

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then sed -n '1,45p' "$0"; exit 0; fi

sc=$(scenario_lower "${1:?usage: run-scenario-tests.sh <a|b|c|d|e> --server HOST [--url-host FQDN] [--client user@host]}")
shift
if ! valid_scenario "$sc"; then
  echo "Invalid scenario" >&2
  exit 1
fi

server=""
url_host_cli=""
client_ssh=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) server="${2:?}"; shift 2 ;;
    --url-host) url_host_cli="${2:?}"; shift 2 ;;
    --client) client_ssh="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "${server:?--server required}" ]]

# Prefer explicit --url-host over env (libvirt passes both; CLI wins).
url_host="${url_host_cli:-${QATBENCH_URL_HOST:-$server}}"

# --client wins over WRK_SSH
wrk_ssh_target="${client_ssh:-${WRK_SSH:-}}"

curl_url=$(bench_url_for_vm "$sc" "$server")
wrk_url=$(bench_url_for_vm "$sc" "$url_host")
log "scenario=${sc} curl_url=${curl_url} wrk_url=${wrk_url} url_host=${url_host}"

if [[ "$sc" == "a" ]]; then
  curl -sfS -o /dev/null --connect-timeout 5 "$curl_url"
else
  curl -sfSk -o /dev/null --connect-timeout 5 "$curl_url"
fi
log "curl OK"

if [[ "$sc" != "a" ]]; then
  sni="${SNI:-$url_host}"
  if command -v openssl >/dev/null 2>&1; then
    log "openssl s_client (SNI=${sni})"
    echo | openssl s_client -connect "${server}:443" -servername "$sni" -brief 2>/dev/null | head -5 || true
  fi
fi

if [[ "${SKIP_WRK:-0}" != "1" ]] && [[ "$sc" == "a" ]]; then
  dur="${WRK_DURATION:-5}"
  threads="${WRK_THREADS:-4}"
  conn="${WRK_CONNECTIONS:-64}"
  if command -v wrk >/dev/null 2>&1; then
    log "wrk CPS smoke (${dur}s, local)"
    "${UTIL_DIR}/wrk-cps-smoke.sh" "$wrk_url" "$dur"
  elif [[ -n "$wrk_ssh_target" ]]; then
    log "wrk CPS smoke (${dur}s, ssh ${wrk_ssh_target})"
    # One remote shell string so -H 'Connection: close' and the URL are not split (ssh -- wrk ... breaks on spaces).
    url_q=$(printf '%q' "$wrk_url")
    # shellcheck disable=SC2029
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$wrk_ssh_target" \
      "wrk -t${threads} -c${conn} -d${dur}s --latency -H 'Connection: close' ${url_q}"
  else
    log "wrk skipped (install wrk on this host, or set WRK_SSH / --client user@bench-client for remote wrk)"
  fi
elif [[ "$sc" != "a" ]]; then
  log "wrk skipped for TLS scenarios (no -k in stock wrk); use curl or run wrk from client with trusted CA"
fi

log "done"

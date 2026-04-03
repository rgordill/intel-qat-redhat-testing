#!/usr/bin/env bash
# Smoke tests for one VM scenario: curl (+ openssl handshake for TLS), optional wrk for (a).
# Requires the server IP/hostname reachable from this host (or run on the client VM).
#
# Usage:
#   ./run-scenario-tests.sh <a|b|c|d|e> --server <host>
# Env:
#   SNI          Server Name for openssl s_client (default: same as --server)
#   SKIP_WRK     set to 1 to skip wrk (default runs wrk only for scenario a)
#   WRK_DURATION seconds (default 5)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

log() { printf '[vm-test] %s\n' "$*"; }

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then sed -n '1,25p' "$0"; exit 0; fi

sc=$(scenario_lower "${1:?usage: run-scenario-tests.sh <a|b|c|d|e> --server HOST}")
shift
if ! valid_scenario "$sc"; then
  echo "Invalid scenario" >&2
  exit 1
fi

server=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server) server="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "${server:?--server required}" ]]

url=$(bench_url_for_vm "$sc" "$server")
log "scenario=${sc} url=${url}"

if [[ "$sc" == "a" ]]; then
  curl -sfS -o /dev/null --connect-timeout 5 "$url"
else
  curl -sfSk -o /dev/null --connect-timeout 5 "$url"
fi
log "curl OK"

if [[ "$sc" != "a" ]]; then
  sni="${SNI:-$server}"
  if command -v openssl >/dev/null 2>&1; then
    log "openssl s_client (SNI=${sni})"
    echo | openssl s_client -connect "${server}:443" -servername "$sni" -brief 2>/dev/null | head -5 || true
  fi
fi

if [[ "${SKIP_WRK:-0}" != "1" ]] && [[ "$sc" == "a" ]] && command -v wrk >/dev/null 2>&1; then
  dur="${WRK_DURATION:-5}"
  log "wrk CPS smoke (${dur}s)"
  "${UTIL_DIR}/wrk-cps-smoke.sh" "$url" "$dur"
elif [[ "$sc" != "a" ]]; then
  log "wrk skipped for TLS scenarios (no -k in stock wrk); use curl or run wrk from client with trusted CA"
fi

log "done"

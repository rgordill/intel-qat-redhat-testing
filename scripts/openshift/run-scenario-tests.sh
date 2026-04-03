#!/usr/bin/env bash
# Curl-based smoke tests against the Ingress hostname (resolve via DNS or /etc/hosts).
#
# Usage:
#   ./run-scenario-tests.sh <a|b|c|d|e> --ingress-host <hostname>
# Env:
#   SKIP_WRK  set 1 to skip wrk for (a)
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

log() { printf '[ocp-test] %s\n' "$*"; }

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then sed -n '1,22p' "$0"; exit 0; fi

sc=$(scenario_lower "${1:?usage: run-scenario-tests.sh <a|b|c|d|e> --ingress-host HOST}")
shift
if ! valid_scenario "$sc"; then echo "Invalid scenario" >&2; exit 1; fi

host=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ingress-host) host="${2:?}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "${host:?--ingress-host required}" ]]

url=$(bench_url_for_ocp "$sc" "$host")
log "scenario=${sc} url=${url}"

if [[ "$sc" == "a" ]]; then
  curl -sfS -o /dev/null --connect-timeout 10 "$url"
else
  curl -sfSk -o /dev/null --connect-timeout 10 "$url"
fi
log "curl OK"

if [[ "$sc" != "a" ]] && command -v openssl >/dev/null 2>&1; then
  log "openssl s_client"
  echo | openssl s_client -connect "${host}:443" -servername "$host" -brief 2>/dev/null | head -5 || true
fi

if [[ "${SKIP_WRK:-0}" != "1" ]] && [[ "$sc" == "a" ]] && command -v wrk >/dev/null 2>&1; then
  dur="${WRK_DURATION:-5}"
  "${UTIL_DIR}/wrk-cps-smoke.sh" "$url" "$dur"
elif [[ "$sc" != "a" ]]; then
  log "wrk skipped for TLS scenarios; use HTTP (a) or wrk with trusted CA on client"
fi

log "done"

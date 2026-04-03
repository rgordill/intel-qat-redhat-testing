# shellcheck shell=bash
# Shared helpers for libvirt / AWS VM benchmark scripts (sourced by deploy-*.sh / run-*.sh).
QAT_BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QAT_BENCH_ROOT
UTIL_DIR="${QAT_BENCH_ROOT}/scripts/utils"

scenario_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

valid_scenario() {
  case "$1" in a|b|c|d|e) return 0 ;; *) return 1 ;; esac
}

# HAProxy listens: (a) port 80; (b–e) port 443 TLS.
bench_url_for_vm() {
  local sc srv
  sc=$(scenario_lower "$1")
  srv=$2
  case "$sc" in
    a) echo "http://${srv}:80/" ;;
    *) echo "https://${srv}:443/" ;;
  esac
}

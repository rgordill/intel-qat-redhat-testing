# shellcheck shell=bash
QAT_BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QAT_BENCH_ROOT
K8S_DIR="${QAT_BENCH_ROOT}/kubernetes"
UTIL_DIR="${QAT_BENCH_ROOT}/scripts/utils"

scenario_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

valid_scenario() {
  case "$1" in a|b|c|d|e) return 0 ;; *) return 1 ;; esac
}

# Replace placeholder host in Ingress manifests (edit INGRESS_HOST for your cluster).
apply_ingress_with_host() {
  local file=$1
  local host=${INGRESS_HOST:?set INGRESS_HOST to your Ingress hostname}
  sed "s|qat-bench.apps.example.com|${host}|g" "$file"
}

bench_url_for_ocp() {
  local sc host
  sc=$(scenario_lower "$1")
  host=$2
  case "$sc" in
    a) echo "http://${host}/" ;;
    *) echo "https://${host}/" ;;
  esac
}

#!/usr/bin/env bash
# Loop scenarios a–e: deploy via Ansible, then run smoke tests against SERVER.
#
# Usage:
#   SERVER=192.168.122.50 ./deploy-and-test-all.sh [extra ansible-playbook args for each deploy]
# Optional: QATBENCH_URL_HOST=bench-server.atik.demo — Host: header / wrk URL hostname (curl still uses SERVER).
# Optional (scenario a wrk): WRK_SSH=cloud-user@<client-ip> so wrk runs on the client VM if not local.
# Example:
#   SERVER=10.0.1.20 ./deploy-and-test-all.sh
#   SERVER=10.0.1.20 QATBENCH_URL_HOST=bench-server.atik.demo ./deploy-and-test-all.sh
#   SERVER=10.0.1.20 WRK_SSH=cloud-user@10.0.1.21 ./deploy-and-test-all.sh
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

srv="${SERVER:?set SERVER to HAProxy host/IP (reachable for curl)}"
urlh=( )
if [[ -n "${QATBENCH_URL_HOST:-}" ]]; then
  urlh=( --url-host "${QATBENCH_URL_HOST}" )
fi

for sc in a b c d e; do
  echo "======== scenario ${sc} ========"
  "${SCRIPT_DIR}/deploy-scenario.sh" "$sc" "$@"
  "${SCRIPT_DIR}/run-scenario-tests.sh" "$sc" --server "$srv" "${urlh[@]}"
done

echo "[vm] all scenarios completed"

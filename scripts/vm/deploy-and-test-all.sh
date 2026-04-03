#!/usr/bin/env bash
# Loop scenarios a–e: deploy via Ansible, then run smoke tests against SERVER.
#
# Usage:
#   SERVER=192.168.122.50 ./deploy-and-test-all.sh [extra ansible-playbook args for each deploy]
# Example:
#   SERVER=10.0.1.20 ./deploy-and-test-all.sh
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

srv="${SERVER:?set SERVER to HAProxy host/IP (reachable for curl)}"

for sc in a b c d e; do
  echo "======== scenario ${sc} ========"
  "${SCRIPT_DIR}/deploy-scenario.sh" "$sc" "$@"
  "${SCRIPT_DIR}/run-scenario-tests.sh" "$sc" --server "$srv"
done

echo "[vm] all scenarios completed"

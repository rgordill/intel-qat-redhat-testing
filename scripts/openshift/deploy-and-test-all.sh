#!/usr/bin/env bash
# Deploy and smoke-test scenarios a–e against INGRESS_HOST.
#
# Usage:
#   INGRESS_HOST=qat-bench.apps.example.com ./deploy-and-test-all.sh
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

: "${INGRESS_HOST:?set INGRESS_HOST}"

for sc in a b c d e; do
  echo "======== scenario ${sc} ========"
  "${SCRIPT_DIR}/deploy-scenario.sh" "$sc"
  "${SCRIPT_DIR}/run-scenario-tests.sh" "$sc" --ingress-host "$INGRESS_HOST"
done

echo "[openshift] all scenarios completed"

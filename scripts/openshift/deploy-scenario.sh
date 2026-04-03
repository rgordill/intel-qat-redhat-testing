#!/usr/bin/env bash
# Deploy nginx + Service + one Ingress matching scenario topology (a–e).
# Scenarios (b) and (c) use the same edge Ingress; (d) and (e) use re-encrypt.
# QAT at the OpenShift router for (c)/(e) is cluster-specific—not represented in YAML.
#
# Prerequisites: kubectl/oc, namespace rights.
# Env:
#   INGRESS_HOST  hostname for Ingress rules (required)
#
# Usage:
#   INGRESS_HOST=qat-bench.apps.cluster.example.com ./deploy-scenario.sh <a|b|c|d|e>
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then sed -n '1,25p' "$0"; exit 0; fi

sc=$(scenario_lower "${1:?scenario a–e required}")
if ! valid_scenario "$sc"; then
  echo "Invalid scenario" >&2
  exit 1
fi

: "${INGRESS_HOST:?set INGRESS_HOST (e.g. qat-bench.apps.ocp.example.com)}"

kubectl apply -f "${K8S_DIR}/namespace.yaml"
kubectl apply -f "${K8S_DIR}/nginx-deployment.yaml"
kubectl apply -f "${K8S_DIR}/service.yaml"

kubectl delete ingress -n qat-bench qat-bench-http qat-bench-edge qat-bench-reencrypt --ignore-not-found=true

case "$sc" in
  a)
    apply_ingress_with_host "${K8S_DIR}/ingress-http-example.yaml" | kubectl apply -f -
    ;;
  b|c)
    apply_ingress_with_host "${K8S_DIR}/ingress-edge-example.yaml" | kubectl apply -f -
    ;;
  d|e)
    apply_ingress_with_host "${K8S_DIR}/ingress-reencrypt-example.yaml" | kubectl apply -f -
    ;;
esac

echo "[openshift] scenario=${sc} applied (host=${INGRESS_HOST})"
echo "[openshift] (d)(e) re-encrypt needs backend TLS + destination CA secret; see kubernetes/ingress-reencrypt-example.yaml"

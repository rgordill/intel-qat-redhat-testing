#!/usr/bin/env bash
# Example: export a subset of OpenShift router-style env vars before manual edits to
# /var/lib/haproxy/conf/haproxy.config (Ansible deploys there; see docs/ROUTER_ENV_MAPPING.md).
# Ansible is the supported path; this script documents parity experiments only.
set -euo pipefail
export ROUTER_MAX_CONNECTIONS="${ROUTER_MAX_CONNECTIONS:-50000}"
export SSL_MIN_VERSION="${SSL_MIN_VERSION:-TLSv1.2}"
export ROUTER_CIPHERS="${ROUTER_CIPHERS:-intermediate}"
export ROUTER_THREADS="${ROUTER_THREADS:-}"
echo "Exported ROUTER_MAX_CONNECTIONS SSL_MIN_VERSION ROUTER_CIPHERS (and optional ROUTER_THREADS)."
echo "See docs/ROUTER_ENV_MAPPING.md and the upstream haproxy-config.template."

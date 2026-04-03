#!/usr/bin/env bash
# Manual gate checks (Stage gates from plan). Run from your workstation with SSH/network access.
# Usage:
#   gates.sh --terraform-outputs /path/to/tf.json
#   gates.sh --client-host USER@IP --server-host USER@IP --scenario a
set -euo pipefail

log() { printf '[gates] %s\n' "$*"; }

check_ssh() {
  local h="${1:?host}"
  log "SSH $h"
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" 'echo ok'
}

check_curl() {
  local url="${1:?url}"
  log "curl $url"
  curl -sfS -o /dev/null "$url" || return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-host) CLIENT="$2"; shift 2 ;;
    --server-host) SERVER="$2"; shift 2 ;;
    --http-url) HTTP_URL="$2"; shift 2 ;;
    --https-url) HTTPS_URL="$2"; shift 2 ;;
    --help|-h)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *) log "unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -n "${CLIENT:-}" ]]; then check_ssh "$CLIENT"; fi
if [[ -n "${SERVER:-}" ]]; then check_ssh "$SERVER"; fi
if [[ -n "${HTTP_URL:-}" ]]; then check_curl "$HTTP_URL"; fi
if [[ -n "${HTTPS_URL:-}" ]]; then curl -sfSk -o /dev/null "$HTTPS_URL" || check_curl "$HTTPS_URL"; fi

log "manual checks complete (extend script for L1–L6 / A / M as needed)"

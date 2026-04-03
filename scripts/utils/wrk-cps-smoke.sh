#!/usr/bin/env bash
# Short CPS-oriented smoke (Connection: close). Usage:
#   scripts/utils/wrk-cps-smoke.sh http://SERVER:80/ 5
#   ./wrk-cps-smoke.sh https://SERVER:443/ 5  (add -k inside if using self-signed)
set -euo pipefail
URL="${1:?URL required}"
DUR="${2:-5}"
THREADS="${WRK_THREADS:-4}"
CONN="${WRK_CONNECTIONS:-64}"
exec wrk -t"${THREADS}" -c"${CONN}" -d"${DUR}s" --latency \
  -H "Connection: close" \
  "${URL}"

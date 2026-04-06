#!/usr/bin/env bash
# Write scripts/vm/scenarios.md (Markdown table) from scenarios.csv for easy reading in GitHub / editors.
# Usage: ./render-scenarios-md.sh [path/to/scenarios.csv]
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CSV="${1:-"${SCRIPT_DIR}/scenarios.csv"}"
OUT="${SCRIPT_DIR}/scenarios.md"
exec python3 "${SCRIPT_DIR}/scenario_csv.py" to-md "$CSV" -o "$OUT"

#!/usr/bin/env bash
# Write scripts/vm/result.md (Markdown table) from result.csv for easy reading in GitHub / editors.
# Usage: ./render-results-md.sh [path/to/result.csv]
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CSV="${1:-"${SCRIPT_DIR}/result.csv"}"
OUT="${SCRIPT_DIR}/result.md"
exec python3 "${SCRIPT_DIR}/scenario_csv.py" results-to-md "$CSV" -o "$OUT"

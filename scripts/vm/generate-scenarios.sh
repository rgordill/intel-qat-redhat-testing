#!/usr/bin/env bash
# Wrapper for generate_scenarios.py — generate scenarios.csv from scenarios.template.yaml.
#
# Usage:
#   ./generate-scenarios.sh --cpus 8 --duration 30
#   ./generate-scenarios.sh --cpus 4 --duration 60 --template /path/to/scenarios.template.yaml -o /path/to/scenarios.csv
#
# Requires: pip install pyyaml
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "${SCRIPT_DIR}/generate_scenarios.py" "$@"

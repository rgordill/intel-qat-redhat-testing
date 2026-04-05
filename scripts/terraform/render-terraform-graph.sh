#!/usr/bin/env bash
# Generate Terraform dependency graphs as Graphviz DOT, PNG, and SVG under docs/terraform.
#
# Requires: terraform (CLI), graphviz (dot).
# First-time init may need network access to download providers.
#
# Usage:
#   ./scripts/terraform/render-terraform-graph.sh
#   ./scripts/terraform/render-terraform-graph.sh terraform/aws
#   OUT_DIR=/tmp/tfgraphs ./scripts/terraform/render-terraform-graph.sh terraform/libvirt
#   ./scripts/terraform/render-terraform-graph.sh --no-init terraform/aws
#
# Extra arguments after -- are passed to `terraform graph` (e.g. -- -type=apply).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/docs/terraform}"
DO_INIT=1
EXTRA_GRAPH_ARGS=()
TF_DIRS=()

usage() {
  cat <<'EOF'
Usage: render-terraform-graph.sh [options] [terraform-dir...] [-- terraform graph args]

Options:
  -h, --help     Show this help
  --no-init      Skip terraform init (use when already initialized)
  -o, --out DIR  Output directory (default: docs/terraform under repo root)

If no terraform-dir is given, processes terraform/aws and terraform/libvirt.

Environment:
  OUT_DIR        Same as -o (default: <repo>/docs/terraform)

Requires: terraform, dot (graphviz).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-init)
      DO_INIT=0
      shift
      ;;
    -o|--out)
      OUT_DIR="${2:?}"
      shift 2
      ;;
    --)
      shift
      EXTRA_GRAPH_ARGS+=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      TF_DIRS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#TF_DIRS[@]} -eq 0 ]]; then
  TF_DIRS=("terraform/aws" "terraform/libvirt")
fi

command -v terraform >/dev/null 2>&1 || {
  echo "terraform not found in PATH" >&2
  exit 1
}
command -v dot >/dev/null 2>&1 || {
  echo "graphviz (dot) not found in PATH; install graphviz to render PNG/SVG" >&2
  exit 1
}

mkdir -p "${OUT_DIR}"

render_one() {
  local rel="$1"
  local abs="${REPO_ROOT}/${rel}"
  local name
  name="$(basename "${abs}")"

  if [[ ! -d "${abs}" ]]; then
    echo "Not a directory: ${abs}" >&2
    return 1
  fi
  if [[ ! -f "${abs}/main.tf" ]] && [[ ! -f "${abs}/main.tf.json" ]]; then
    echo "No main.tf in ${abs}; skipping" >&2
    return 1
  fi

  echo "==> ${rel}"
  (
    cd "${abs}"
    if [[ "${DO_INIT}" -eq 1 ]]; then
      terraform init -input=false -backend=false
    fi
    terraform graph "${EXTRA_GRAPH_ARGS[@]}" >"${OUT_DIR}/${name}-graph.dot"
  )

  dot -Tpng -o"${OUT_DIR}/${name}-graph.png" "${OUT_DIR}/${name}-graph.dot"
  dot -Tsvg -o"${OUT_DIR}/${name}-graph.svg" "${OUT_DIR}/${name}-graph.dot"
  echo "    Wrote ${OUT_DIR}/${name}-graph.{dot,png,svg}"
}

for rel in "${TF_DIRS[@]}"; do
  render_one "${rel}"
done

echo "Done."

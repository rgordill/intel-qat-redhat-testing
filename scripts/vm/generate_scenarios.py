#!/usr/bin/env python3
"""Generate scripts/vm/scenarios.csv from scenarios.template.yaml.

For each base scenario, emits rows for every combination of:
  - wrk_threads: 1, 2, 4, ... doubling until client CPU limit (last step is the limit if not a power of two)
  - connection multiplier: 1, 2, 4, 8, 16 (× per CPU → wrk_connections = threads * multiplier)

Requires: pip install pyyaml
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError as e:
    print("ERROR: PyYAML is required: pip install pyyaml", file=sys.stderr)
    raise SystemExit(1) from e

CSV_FIELDS = [
    "id",
    "name",
    "topology",
    "router_analogue",
    "target_url",
    "wrk_run",
    "wrk_threads",
    "wrk_connections",
    "wrk_duration_sec",
]

# 1× .. 16× connections per CPU, doubling each step
CONN_MULTIPLIERS = (1, 2, 4, 8, 16)


def thread_values(max_cpus: int) -> list[int]:
    """1, 2, 4, … doubling until max_cpus (inclusive), capped at client limit."""
    if max_cpus < 1:
        return []
    out: list[int] = []
    v = 1
    while v < max_cpus:
        out.append(v)
        nxt = v * 2
        if nxt > max_cpus:
            out.append(max_cpus)
            return out
        v = nxt
    out.append(max_cpus)
    return out


def load_template(path: Path) -> list[dict]:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not raw or "scenarios" not in raw:
        raise SystemExit(f"Invalid template: expected top-level 'scenarios' list in {path}")
    scenarios = raw["scenarios"]
    if not isinstance(scenarios, list):
        raise SystemExit("template 'scenarios' must be a list")
    out = []
    for i, row in enumerate(scenarios):
        if not isinstance(row, dict):
            raise SystemExit(f"scenarios[{i}] must be a mapping")
        for key in ("id", "name", "topology", "router_analogue", "target_url", "wrk_run"):
            if key not in row:
                raise SystemExit(f"scenarios[{i}] missing key: {key}")
        out.append({k: str(row[k]).strip() if row[k] is not None else "" for k in row})
    return out


def main() -> None:
    here = Path(__file__).resolve().parent
    p = argparse.ArgumentParser(
        description="Generate scenarios.csv from scenarios.template.yaml (wrk grid)."
    )
    p.add_argument(
        "--template",
        type=Path,
        default=here / "scenarios.template.yaml",
        help="YAML template path (default: alongside this script)",
    )
    p.add_argument(
        "-o",
        "--output",
        type=Path,
        default=here / "scenarios.csv",
        help="Output CSV path",
    )
    p.add_argument(
        "--cpus",
        type=int,
        required=True,
        help="Client host vCPU count (max wrk_threads)",
    )
    p.add_argument(
        "--duration",
        type=int,
        required=True,
        help="wrk duration per row in seconds",
    )
    args = p.parse_args()

    if args.cpus < 1:
        raise SystemExit("--cpus must be >= 1")
    if args.duration < 1:
        raise SystemExit("--duration must be >= 1")

    if not args.template.is_file():
        raise SystemExit(f"Template not found: {args.template}")

    base_rows = load_template(args.template)
    threads = thread_values(args.cpus)

    generated: list[dict[str, str]] = []
    for base in base_rows:
        bid = base["id"]
        for t in threads:
            for mult in CONN_MULTIPLIERS:
                conn = t * mult
                rid = f"{bid}-w{t}-x{mult}"
                name = f"{base['name']} ({t}T × {mult}×conn)"
                generated.append(
                    {
                        "id": rid,
                        "name": name,
                        "topology": base["topology"],
                        "router_analogue": base["router_analogue"],
                        "target_url": base["target_url"],
                        "wrk_run": base["wrk_run"],
                        "wrk_threads": str(t),
                        "wrk_connections": str(conn),
                        "wrk_duration_sec": str(args.duration),
                    }
                )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS, lineterminator="\n")
        w.writeheader()
        w.writerows(generated)

    print(
        f"Wrote {len(generated)} rows to {args.output} "
        f"(cpus={args.cpus} → threads={threads}, mults={list(CONN_MULTIPLIERS)}, duration={args.duration}s)"
    )
    print("Refresh Markdown: scripts/vm/render-scenarios-md.sh")


if __name__ == "__main__":
    main()

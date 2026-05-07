#!/usr/bin/env python3
"""Parse scripts/vm/scenarios.csv — lookup fields, list ids, emit Markdown tables.

Also supports generic CSV (e.g. result.csv) for Markdown export via results-to-md.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
import sys
from pathlib import Path


def _inventory_helpers():
    """Load inventory_from_ansible from the same directory (script invocation, not package)."""
    path = Path(__file__).resolve().parent / "inventory_from_ansible.py"
    spec = importlib.util.spec_from_file_location("qatbench_inventory_from_ansible", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _ansible_dir(cli_dir: Path | None) -> Path:
    if cli_dir is not None:
        return cli_dir
    root = os.environ.get("QAT_BENCH_ROOT")
    if root:
        return Path(root) / "ansible"
    return Path(__file__).resolve().parent.parent.parent / "ansible"


def read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames or [])
        if not fieldnames:
            raise SystemExit(f"empty or invalid CSV: {path}")
        rows = []
        for row in reader:
            rid = (row.get("id") or "").strip()
            if not rid:
                continue
            rows.append({k: (v or "").strip() for k, v in row.items()})
        return fieldnames, rows


def read_rows_all(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    """All data rows from CSV (no filter on `id`). For result.csv and similar."""
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames or [])
        if not fieldnames:
            raise SystemExit(f"empty or invalid CSV: {path}")
        rows: list[dict[str, str]] = []
        for row in reader:
            rows.append({k: (v or "").strip() for k, v in row.items()})
        return fieldnames, rows


def row_by_id(rows: list[dict[str, str]], sid: str) -> dict[str, str] | None:
    sid = sid.strip().lower()
    for row in rows:
        if row.get("id", "").strip().lower() == sid:
            return row
    return None


def cmd_get(path: Path, sid: str, field: str) -> None:
    _, rows = read_rows(path)
    row = row_by_id(rows, sid)
    if row is None:
        sys.exit(1)
    if field not in row:
        sys.exit(2)
    print(row[field])


def cmd_ids(path: Path) -> None:
    _, rows = read_rows(path)
    for row in rows:
        print(row["id"])


def cmd_to_md(path: Path, out: Path | None) -> None:
    fields, rows = read_rows(path)
    lines: list[str] = [
        "# Benchmark scenarios",
        "",
        f"Generated from [`scenarios.csv`](scenarios.csv) — refresh with `scripts/vm/render-scenarios-md.sh`.",
        "",
        "| " + " | ".join(fields) + " |",
        "| " + " | ".join("---" for _ in fields) + " |",
    ]
    for row in rows:
        cells = []
        for f in fields:
            cell = row.get(f, "").replace("|", "\\|").replace("\n", " ")
            cells.append(cell)
        lines.append("| " + " | ".join(cells) + " |")
    text = "\n".join(lines) + "\n"
    if out:
        out.write_text(text, encoding="utf-8")
        print(str(out))
    else:
        sys.stdout.write(text)


def cmd_render_target_url(
    path: Path,
    sid: str,
    inv_rel: str | None,
    vars_json_file: Path | None,
    ansible_dir: Path | None,
) -> None:
    """Expand scenarios.csv target_url using Ansible-merged vars (Jinja2) and legacy <qatbench_vm_domain>."""
    _, rows = read_rows(path)
    row = row_by_id(rows, sid)
    if row is None:
        sys.exit(1)
    tpl = row.get("target_url") or ""

    needs_vars = "{{" in tpl or "{%" in tpl or "<qatbench_vm_domain>" in tpl
    vars_: dict[str, object] = {}

    inv_mod = None
    if needs_vars:
        if vars_json_file is not None and vars_json_file.is_file():
            vars_ = json.loads(vars_json_file.read_text(encoding="utf-8"))
            if not isinstance(vars_, dict):
                print("ERROR: vars-json-file must contain a JSON object", file=sys.stderr)
                sys.exit(1)
        elif inv_rel:
            ad = _ansible_dir(ansible_dir)
            if not ad.is_dir():
                print(f"ERROR: ansible dir not found: {ad}", file=sys.stderr)
                sys.exit(1)
            inv_mod = _inventory_helpers()
            vars_ = inv_mod.load_bench_server_hostvars(ad, inv_rel)
        else:
            print(
                "ERROR: templated target_url requires ansible inventory path or --vars-json-file",
                file=sys.stderr,
            )
            sys.exit(1)

    if "{{" in tpl or "{%" in tpl:
        if inv_mod is None:
            inv_mod = _inventory_helpers()
        out = inv_mod.render_inventory_jinja(tpl, vars_)
    else:
        out = tpl

    if "<qatbench_vm_domain>" in out:
        dom = str(vars_.get("qatbench_vm_domain") or "").strip()
        out = out.replace("<qatbench_vm_domain>", dom)

    sys.stdout.write(out + ("\n" if not out.endswith("\n") else ""))


def cmd_results_to_md(path: Path, out: Path | None) -> None:
    fields, rows = read_rows_all(path)
    lines: list[str] = [
        "# Benchmark results",
        "",
        f"Generated from [`result.csv`](result.csv) — refresh with `scripts/vm/render-results-md.sh`.",
        "",
        "| " + " | ".join(fields) + " |",
        "| " + " | ".join("---" for _ in fields) + " |",
    ]
    for row in rows:
        cells = []
        for f in fields:
            cell = row.get(f, "").replace("|", "\\|").replace("\n", " ")
            cells.append(cell)
        lines.append("| " + " | ".join(cells) + " |")
    text = "\n".join(lines) + "\n"
    if out:
        out.write_text(text, encoding="utf-8")
        print(str(out))
    else:
        sys.stdout.write(text)


def main() -> None:
    p = argparse.ArgumentParser(description="scenarios.csv helpers")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("get", help="print field value for scenario id")
    g.add_argument("csv_path", type=Path)
    g.add_argument("id")
    g.add_argument("field")

    i = sub.add_parser("ids", help="print one scenario id per line")
    i.add_argument("csv_path", type=Path)

    m = sub.add_parser("to-md", help="write Markdown table (stdout or --out)")
    m.add_argument("csv_path", type=Path)
    m.add_argument("-o", "--out", type=Path, default=None)

    r = sub.add_parser("results-to-md", help="write result.csv as Markdown table (stdout or --out)")
    r.add_argument("csv_path", type=Path)
    r.add_argument("-o", "--out", type=Path, default=None)

    u = sub.add_parser(
        "render-target-url",
        help="print target_url for scenario id (Jinja2 + merged bench-server vars; legacy <qatbench_vm_domain>)",
    )
    u.add_argument("csv_path", type=Path)
    u.add_argument("id")
    u.add_argument(
        "--inventory",
        "-i",
        default=None,
        help="inventory path relative to ansible dir (e.g. inventory/hosts.auto.yml)",
    )
    u.add_argument(
        "--vars-json-file",
        type=Path,
        default=None,
        help="merged bench-server JSON from inventory_from_ansible.py --bench-server-vars-json (avoids repeated ansible-inventory)",
    )
    u.add_argument("--ansible-dir", type=Path, default=None, help="directory containing ansible.cfg")

    args = p.parse_args()
    if args.cmd == "get":
        cmd_get(args.csv_path, args.id, args.field)
    elif args.cmd == "ids":
        cmd_ids(args.csv_path)
    elif args.cmd == "to-md":
        cmd_to_md(args.csv_path, args.out)
    elif args.cmd == "results-to-md":
        cmd_results_to_md(args.csv_path, args.out)
    elif args.cmd == "render-target-url":
        cmd_render_target_url(
            args.csv_path,
            args.id,
            args.inventory,
            args.vars_json_file,
            args.ansible_dir,
        )


if __name__ == "__main__":
    main()

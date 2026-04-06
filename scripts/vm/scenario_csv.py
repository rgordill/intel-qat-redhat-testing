#!/usr/bin/env python3
"""Parse scripts/vm/scenarios.csv — lookup fields, list ids, emit Markdown tables.

Also supports generic CSV (e.g. result.csv) for Markdown export via results-to-md.
"""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


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

    args = p.parse_args()
    if args.cmd == "get":
        cmd_get(args.csv_path, args.id, args.field)
    elif args.cmd == "ids":
        cmd_ids(args.csv_path)
    elif args.cmd == "to-md":
        cmd_to_md(args.csv_path, args.out)
    elif args.cmd == "results-to-md":
        cmd_results_to_md(args.csv_path, args.out)


if __name__ == "__main__":
    main()

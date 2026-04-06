#!/usr/bin/env python3
"""
Resolve benchmark server/client connection details from Ansible inventory (same merge as playbooks).

Uses `ansible-inventory --list` so group_vars/all.yml, host vars, and inventory `all.vars`
are reflected — not raw YAML line parsing.

Usage:
  inventory_from_ansible.py <inventory_rel_path> [--ansible-dir DIR]

Prints shell `export VAR='...'` lines for: BENCH_PROVIDER, BENCH_SERVER_IP, BENCH_CLIENT_IP,
BENCH_SERVER_USER, BENCH_CLIENT_USER, BENCH_VM_DOMAIN, BENCH_SERVER_FQDN, BENCH_CLIENT_FQDN, BENCH_URL_HOST
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


def _run_inventory(ansible_dir: Path, inv_rel: str) -> dict:
    proc = subprocess.run(
        ["ansible-inventory", "-i", inv_rel, "--list"],
        cwd=str(ansible_dir),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout or "ansible-inventory failed\n")
        raise SystemExit(proc.returncode)
    return json.loads(proc.stdout)


def _hostvars(data: dict) -> dict:
    meta = data.get("_meta") or {}
    return meta.get("hostvars") or {}


def _export_line(name: str, value: str) -> str:
    return f"export {name}={shlex.quote(value)}"


def export_shell(ansible_dir: Path, inv_rel: str) -> None:
    data = _run_inventory(ansible_dir, inv_rel)
    hv = _hostvars(data)
    srv = hv.get("bench-server") or {}
    cli = hv.get("bench-client") or {}

    server_ip = str(srv.get("ansible_host") or "").strip()
    client_ip = str(cli.get("ansible_host") or "").strip()
    server_user = str(srv.get("ansible_user") or "").strip()
    client_user = str(cli.get("ansible_user") or "").strip()

    domain = str(srv.get("qatbench_vm_domain") or cli.get("qatbench_vm_domain") or "").strip()
    if not domain:
        domain = str(srv.get("qatbench_aws_domain") or cli.get("qatbench_aws_domain") or "").strip()

    server_fqdn = str(srv.get("qatbench_server_fqdn") or "").strip()
    client_fqdn = str(cli.get("qatbench_client_fqdn") or "").strip()

    prov = str(srv.get("provider") or cli.get("provider") or "").strip() or "libvirt"

    # URL/SNI hostname for HAProxy tests: same FQDN playbooks use (inventory / terraform output).
    url_host = server_fqdn
    if not url_host and domain:
        url_host = f"bench-server.{domain}"
    if not url_host:
        url_host = server_ip

    out = [
        _export_line("BENCH_PROVIDER", prov),
        _export_line("BENCH_SERVER_IP", server_ip),
        _export_line("BENCH_CLIENT_IP", client_ip),
        _export_line("BENCH_SERVER_USER", server_user),
        _export_line("BENCH_CLIENT_USER", client_user),
        _export_line("BENCH_VM_DOMAIN", domain),
        _export_line("BENCH_SERVER_FQDN", server_fqdn),
        _export_line("BENCH_CLIENT_FQDN", client_fqdn),
        _export_line("BENCH_URL_HOST", url_host),
    ]
    sys.stdout.write("\n".join(out) + "\n")


def main() -> None:
    p = argparse.ArgumentParser(description="Bench inventory via ansible-inventory")
    p.add_argument(
        "inventory_rel",
        help="Inventory path relative to ansible dir, e.g. inventory/hosts.auto.yml",
    )
    p.add_argument(
        "--ansible-dir",
        type=Path,
        default=None,
        help="Directory containing ansible.cfg (default: <repo>/ansible from QAT_BENCH_ROOT or parent of scripts/vm)",
    )
    args = p.parse_args()

    root = os.environ.get("QAT_BENCH_ROOT")
    if args.ansible_dir is not None:
        ansible_dir = args.ansible_dir
    elif root:
        ansible_dir = Path(root) / "ansible"
    else:
        ansible_dir = Path(__file__).resolve().parent.parent.parent / "ansible"

    if not ansible_dir.is_dir():
        print(f"ERROR: ansible dir not found: {ansible_dir}", file=sys.stderr)
        sys.exit(1)

    export_shell(ansible_dir, args.inventory_rel)


if __name__ == "__main__":
    main()

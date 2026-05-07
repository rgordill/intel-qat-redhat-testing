#!/usr/bin/env python3
"""
Resolve benchmark server/client connection details from Ansible inventory (same merge as playbooks).

Uses `ansible-inventory --list` so group_vars/all.yml, host vars, and inventory `all.vars`
are reflected — not raw YAML line parsing.

Usage:
  inventory_from_ansible.py <inventory_rel_path> [--ansible-dir DIR]

Prints shell `export VAR='...'` lines for: BENCH_PROVIDER, BENCH_SERVER_IP, BENCH_CLIENT_IP,
BENCH_SERVER_USER, BENCH_CLIENT_USER, BENCH_VM_DOMAIN, BENCH_SERVER_FQDN, BENCH_CLIENT_FQDN, BENCH_URL_HOST

With --bench-server-vars-json, prints merged host vars for bench-server only (JSON), for Jinja2 rendering of scenarios.csv target_url (same merge as playbooks).
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

try:
    import jinja2
except ImportError:  # pragma: no cover - optional until templated URLs used
    jinja2 = None


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


def load_bench_server_hostvars(ansible_dir: Path, inv_rel: str) -> dict:
    """Merged variables visible on bench-server (inventory + group_vars), same as ansible-inventory hostvars."""
    data = _run_inventory(ansible_dir, inv_rel)
    hv = _hostvars(data)
    srv = hv.get("bench-server")
    if not isinstance(srv, dict):
        return {}
    return dict(srv)


def render_inventory_jinja(template: str, variables: dict) -> str:
    """Resolve Ansible-style {{ ... }} / {% ... %} using merged host var dict as template root.

    Ansible inventory YAML often nests templates (e.g. ansible_host: '{{ qatbench_server_fqdn }}'
    while qatbench_server_fqdn itself contains '{{ qatbench_vm_domain }}'). Re-render until stable
    (bounded passes), mirroring playbook-time resolution enough for scenario URLs.
    """
    if jinja2 is None:
        sys.stderr.write(
            "ERROR: jinja2 is required for Ansible-style templates in scenarios.csv target_url.\n"
            "Install: pip install jinja2   (or install ansible, which depends on jinja2)\n"
        )
        raise SystemExit(1)
    env = jinja2.Environment(
        autoescape=False,
        undefined=jinja2.StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=False,
    )
    out = template
    for _ in range(16):
        if "{{" not in out and "{%" not in out:
            break
        nxt = env.from_string(out).render(**variables)
        if nxt == out:
            break
        out = nxt
    return out


def expand_host_templates(value: str, variables: dict) -> str:
    """Resolve nested {{ }} in inventory-derived strings (ansible_host, fqdn, …) using that host's merged vars."""
    s = (value or "").strip()
    if not s or ("{{" not in s and "{%" not in s):
        return s
    if jinja2 is None:
        sys.stderr.write(
            "[bench] WARN: jinja2 missing; inventory templates (e.g. ansible_host) will not expand. "
            "Install jinja2 or use literal ansible_host in inventory.\n"
        )
        return s
    return render_inventory_jinja(s, variables)


def _export_line(name: str, value: str) -> str:
    return f"export {name}={shlex.quote(value)}"


def export_shell(ansible_dir: Path, inv_rel: str) -> None:
    data = _run_inventory(ansible_dir, inv_rel)
    hv = _hostvars(data)
    srv = hv.get("bench-server") or {}
    cli = hv.get("bench-client") or {}
    if not isinstance(srv, dict):
        srv = {}
    if not isinstance(cli, dict):
        cli = {}
    srv = dict(srv)
    cli = dict(cli)

    server_ip = expand_host_templates(str(srv.get("ansible_host") or ""), srv)
    client_ip = expand_host_templates(str(cli.get("ansible_host") or ""), cli)
    server_user = str(srv.get("ansible_user") or "").strip()
    client_user = str(cli.get("ansible_user") or "").strip()

    domain_ctx = srv if srv else cli
    domain = expand_host_templates(
        str(srv.get("qatbench_vm_domain") or cli.get("qatbench_vm_domain") or ""),
        domain_ctx,
    ).strip()
    if not domain:
        domain = expand_host_templates(
            str(srv.get("qatbench_aws_domain") or cli.get("qatbench_aws_domain") or ""),
            domain_ctx,
        ).strip()

    server_fqdn = expand_host_templates(str(srv.get("qatbench_server_fqdn") or ""), srv).strip()
    client_fqdn = expand_host_templates(str(cli.get("qatbench_client_fqdn") or ""), cli).strip()

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
    p.add_argument(
        "--bench-server-vars-json",
        action="store_true",
        help="Print merged bench-server host vars as JSON (for scenarios.csv Jinja2 rendering)",
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

    if args.bench_server_vars_json:
        srv = load_bench_server_hostvars(ansible_dir, args.inventory_rel)
        json.dump(srv, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return

    export_shell(ansible_dir, args.inventory_rel)


if __name__ == "__main__":
    main()

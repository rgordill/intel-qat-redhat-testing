# QAT vs CPU TLS — observability automation and findings summary

This document describes the **perf / eBPF / HAProxy metrics automation** added for comparing Intel **qatengine** offload with ordinary CPU TLS, how to run it, how to read the artifacts, and **what was verified in this repository session**.

---

## What was implemented

### Ansible role `qatbench_observability`

| Deliverable | Purpose |
|-------------|---------|
| Packages **`perf`**, **`bpftrace`**, **`socat`**, **`curl`**, **`procps-ng`** | CPU profiling, short eBPF sample, HAProxy stats socket and Prometheus scrape |
| **`/usr/local/sbin/qatbench-observability-snapshot.sh`** | Single-shot bundle under **`/var/lib/qatbench/observability/`** |

The snapshot script collects, per run:

1. **Host / kernel** (`01-host.txt`): `uname`, `uptime`, `openssl version`, boot `cmdline`, `sysctl` for TCP ULP (kTLS visibility).
2. **HAProxy binary** (`03-haproxy-binary.txt`): `haproxy -vv` filtered for OpenSSL/engine flags (`USE_ENGINE`, etc.).
3. **OpenSSL engine** (`04-openssl-engine.txt`): `openssl engine -c -t qatengine` (falls back to listing engines if that fails).
4. **QAT runtime** (`05-qat-runtime.txt`): `systemctl status qat.service`, `/dev/vfio`, QAT-related **`lspci`** lines, **`/proc/interrupts`** lines matching QAT/ICP.
5. **QAT hardware telemetry** (`05b-qat-telemetry.txt`): firmware counters from **`/sys/kernel/debug/qat/`** (`fw_counters`, `cnv_errors`, `heartbeat`) and sysfs telemetry nodes — confirms whether crypto operations are actually reaching the QAT hardware.
6. **HAProxy process** (`06-haproxy-process.txt`): `pidof haproxy`, per-PID **`/proc/<pid>/status`** (threads, voluntary/involuntary context switches), **`/proc/<pid>/sched`** (scheduler stats), and **`/proc/<pid>/maps`** filtered for OpenSSL/QAT-related mappings.
7. **Stats socket** (`07-haproxy-socket.txt`): `show info`, `show pools`, `show ssl stats`, head of `show stat`.
8. **Prometheus exporter** (`08-prometheus-scrape.txt`): `curl` of **`http://127.0.0.1:8405/metrics`** and **`/`**, plus grep for TLS/SSL-related lines.
9. **`perf stat`** (`09-perf-stat.txt`): hardware counters on all HAProxy PIDs for **`qatbench_perf_stat_seconds`** (default **15**): cycles, instructions, IPC, cache behaviour, TMA breakdown.
10. **`perf report` snapshot** (`09b-perf-report-snapshot.txt`): always-on lightweight `perf record` + `perf report --stdio` for the same duration as `perf stat`, providing **function-level hot path identification** (top 600 lines of the report). The temporary `perf.data` is deleted after report generation to save space. Uses DWARF call graphs for accurate user-space stacks.
11. **Optional deep `perf record`** (off by default): full **`perf.data`** retained on disk when **`qatbench_perf_record_enable`** is true, for offline flame-graph generation.
12. **bpftrace user-space stack profile** (`11-bpftrace-profile.txt`, default **10** s): `profile:hz:99` with **`ustack(perf, 32)`** aggregation — produces flame-graph-compatible stack traces showing which user-space functions consume CPU. May fail if BTF/kernel constraints are tight — failure is logged, not fatal.
13. **bpftrace kernel+user stack profile** (`11b-bpftrace-kstack.txt`): combined **`kstack + ustack`** profile revealing the full path from kernel syscall entry through user-space crypto functions.

Each run produces **`run-<UTC-timestamp>/`**, a **`latest`** symlink, and **`run-<timestamp>.tar.gz`** plus **`latest.tar.gz`** for easy fetch.

Defaults live in:

`ansible/roles/qatbench_observability/defaults/main.yml`

### Playbooks and wiring

- **`ansible/playbooks/deploy_benchmark.yml`** — runs **`qatbench_observability`** on **`server`** after **`haproxy_server`** (tag **`observability`**).
- **`ansible/playbooks/collect_observability.yml`** — (re)installs tooling, runs the snapshot **as root**, and **`fetch`**es **`latest.tar.gz`** to **`ansible/artifacts/qatbench_observability/<inventory_hostname>-latest.tar.gz`**.

Fetched bundles are **gitignored** (`ansible/artifacts/qatbench_observability/*.tar.gz`).

---

## How to run (recommended workflow)

### 1. Deploy (includes observability packages)

```bash
cd ansible
ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml
```

Skip only observability with tags if ever needed:

```bash
ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml --skip-tags observability
```

### 2. Generate load

Use your normal load generator (wrk, vegeta, etc.) so HAProxy is busy **during** the snapshot; otherwise `perf stat` reflects idle behaviour.

### 3. Collect bundle

```bash
ansible-playbook -i inventory/hosts.auto.yml playbooks/collect_observability.yml \
  -e qatbench_perf_stat_seconds=30
```

Optional deeper capture:

```bash
ansible-playbook -i inventory/hosts.auto.yml playbooks/collect_observability.yml \
  -e qatbench_perf_stat_seconds=60 \
  -e qatbench_perf_record_enable=true \
  -e qatbench_perf_record_seconds=15
```

### 4. Compare QAT on vs off

Run the same load profile twice:

1. **`enable_qat: true`** (qatengine + `ssl-mode-async`) — deploy, load, **`collect_observability.yml`**.
2. **`enable_qat: false`** — redeploy (stock HAProxy path from role), same load, collect again.

Diff the tarballs: especially **`09b-perf-report-snapshot.txt`** (function hot paths), **`11-bpftrace-profile.txt`** (user-space stacks), **`05b-qat-telemetry.txt`** (QAT hw counters), **`09-perf-stat.txt`** (CPU profile), **`07-haproxy-socket.txt`**, **`04-openssl-engine.txt`**.

---

## Operational notes

- **`perf stat` and `perf record`** require permission to attach to HAProxy PIDs; the playbook runs the script as **root**.
- **`09b-perf-report-snapshot.txt`** is always-on and provides function-level hot paths. For richer stacks with inlined frames, install **debuginfo**: `dnf debuginfo-install haproxy openssl-libs` on RHEL.
- **`bpftrace`** needs a usable BPF environment (BTF, sufficient privileges). If **`11-bpftrace-profile.txt`** shows errors, the **`09b`** perf report is the fallback for hot path analysis.
- **`05b-qat-telemetry.txt`** reads QAT debugfs/sysfs counters. If empty, `debugfs` may not be mounted or QAT driver telemetry is disabled — `mount -t debugfs none /sys/kernel/debug` and verify.
- If **`show ssl stats`** is unsupported on your exact HAProxy build, that section of **`07-haproxy-socket.txt`** will show an error — **`show info`** and Prometheus scrapes remain useful.

---

## Related documentation

- [HAPROXY_QAT_ENGINE_OVERVIEW.md](./HAPROXY_QAT_ENGINE_OVERVIEW.md) — QAT prerequisites and HAProxy engine configuration path.

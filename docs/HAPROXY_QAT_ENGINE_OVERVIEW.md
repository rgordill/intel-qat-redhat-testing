# HAProxy with Intel QAT OpenSSL engine — high-level overview

This document summarizes **what must happen** for HAProxy to use the Intel **qatengine** OpenSSL engine on RHEL 9+, in the same order as the Ansible automation in this repository. For SRPM rebuild details and manual commands, see [HAPROXY_USE_ENGINE_BUILD.md](./HAPROXY_USE_ENGINE_BUILD.md).

## Why several roles are needed

1. **Stock HAProxy on RHEL AppStream is usually built without `USE_ENGINE=1`**, so global directives such as `ssl-engine` are unavailable. You need a binary rebuilt from Red Hat’s HAProxy source RPM with that flag enabled (`haproxy_qat_build`).
2. **QAT hardware access for userspace** requires correct kernel parameters, VFIO binding for QAT virtual functions, Intel **qatlib** / **qatengine** packages, and the **qat.service** manager (`qat_prereqs`).
3. **Running HAProxy as a non-root service** still needs access to VFIO character devices, adequate locked memory for DMA maps, ordering relative to **qat.service**, and (under SELinux enforcing) a small custom policy so **haproxy_t** may use VFIO (`haproxy_server`).

## Automation order (`deploy_benchmark.yml`)

When `enable_qat` is true on the **server** host, the play runs:

1. **`rhel_subscription`** — ensures RHSM/RHUI can reach BaseOS, AppStream, and (for the rebuild) **AppStream source** repositories.
2. **`qat_prereqs`** — kernel cmdline, QAT packages, VFIO udev, **qat.service**.
3. **`haproxy_qat_build`** — enables source repos if needed, rebuilds HAProxy from the Red Hat SRPM with **`USE_ENGINE=1`**, installs the RPMs, writes a **marker file** under `/var/lib/qatbench/`.
4. **`haproxy_server`** — refuses QAT mode without that marker; configures HAProxy, systemd overrides, SELinux (if enforcing), limits, and starts the service.

Non-QAT deployments skip `qat_prereqs` and `haproxy_qat_build`; **`haproxy_server`** installs the pinned distro HAProxy package instead.

---

## Step 1 — Subscription and repositories (`rhel_subscription`)

You need a registered RHEL 9+ host so **`dnf`** can install build tools, **qatlib**, and dependencies.

For **`haproxy_qat_build`**, the **AppStream source** repository must be reachable so **`dnf download --source haproxy`** can fetch Red Hat’s SRPM. The role discovers repo IDs (CDN vs cloud RHUI), enables them with **`subscription-manager repos --enable`** (the Ansible module **`rhsm_repository`** is avoided for some RHUI IDs the CLI accepts), optionally enables **CodeReady Builder** (CRB) for build dependencies, and may use **`dnf config-manager --set-enabled`** for RHUI repo stanzas that stay disabled until toggled.

---

## Step 2 — Intel QAT prerequisites (`qat_prereqs`)

### Kernel and firmware

- **`intel_iommu=on`** must be present on the kernel command line (applied with **`grubby`** when missing).
- **`vfio-pci.ids=…`** must list the **QAT virtual function** PCI IDs your guest exposes (the role discovers **`8086:4940|4941|4943|4945|4947`** via **`lspci -nn`**, or you set **`qat_prereqs_vfio_pci_ids_override`**).
- If grub changes were applied and **`qat_prereqs_reboot_after_kernel_cmdline_changes`** is true, the role reboots so **`/proc/cmdline`** matches before continuing.

These align with [Intel QATlib system requirements](https://intel.github.io/quickassist/qatlib/requirements.html).

### Packages and services

Install **`qatlib`**, **`qatlib-service`**, and **`qatengine`** (defaults in **`qat_prereqs`**). **qatengine** is the OpenSSL engine HAProxy loads by name in **`ssl-engine`**.

### VFIO device nodes

Deploy udev rules so users in the **`qat`** group can access **`/dev/vfio/<n>`**, reload udev, enable and start **`qat.service`** (**qatmgr**), and restart QAT if rules changed so VFIO nodes pick up permissions.

Operational notes are written to **`/etc/qat-bench/README-intel-qat.txt`** on the host.

---

## Step 3 — HAProxy built with OpenSSL engine support (`haproxy_qat_build`)

Purpose: produce an HAProxy RPM whose **`haproxy -vv`** output shows **`USE_ENGINE`**, so configuration may use **`ssl-engine`**.

At a high level the role:

1. **Decides whether to rebuild** — skips when the marker file exists, **`haproxy`** already reports **`USE_ENGINE`**, and **`haproxy_qat_build_force`** is false (**`rebuild_context.yml`**).
2. **Resolves and enables AppStream source** (and optional CRB / RHUI toggles) — **`source_repo_phase.yml`**.
3. Installs **`rpm-build`** and **`dnf-plugins-core`**, creates **`rpmbuild`** directories, **`dnf download --source haproxy`**, **`rpm -ivh`** the SRPM into **`_topdir`**.
4. Patches **`haproxy.spec`** so **`USE_ENGINE=1`** appears alongside **`USE_OPENSSL`** in **`%build`**.
5. Installs **`lua-devel`** (SRPM BuildRequires nuance), **`dnf builddep`** on the spec, **`rpmbuild -bb`**, **`dnf install`** the produced **`haproxy-*.rpm`** (excluding debug packages).
6. Writes **`haproxy_qat_build_marker_path`** (default **`/var/lib/qatbench/haproxy-use-engine-from-src`**) so **`haproxy_server`** does not reinstall the distro-pinned **`haproxy-2.8*`** package over your build.

Only Red Hat sources are used — not third-party HAProxy SRPMs.

---

## Step 4 — HAProxy service integration (`haproxy_server`)

### Binary and package policy

- With **`enable_qat`**, the role **asserts** the **`haproxy_qat_build`** marker exists; otherwise it fails fast.
- It **does not** **`dnf install`** the distro HAProxy spec when QAT is enabled (the rebuilt RPM is already installed).

### Identity and permissions

- Add user **`haproxy`** to supplemental group **`qat`** so it can open VFIO nodes governed by the udev rules.

### SELinux (enforcing only)

Default policy can deny **haproxy_t** access to VFIO devices used by **qatengine**. The role installs **`checkpolicy`** / **`policycoreutils-devel`**, stages **`qatbench_haproxy_vfio.te`**, and loads a compiled module (**`semodule -i`**).

### Configuration template

Global section (**`haproxy.config.j2`**) adds:

- **`ssl-engine {{ haproxy_qat_openssl_engine }} algo {{ haproxy_qat_ssl_engine_algo }}`** (defaults: **`qatengine`**, **`ALL`**).
- **`ssl-mode-async`** — async handshakes when using the engine path.

### systemd overrides (**`haproxy.service.d-qatbench.conf.j2`**)

With QAT:

- **`After=`** / **`Wants=`** **`qat.service`** so **qatmgr** runs before HAProxy.
- **`LimitMEMLOCK=infinity`** — VFIO DMA mapping may require unlimited locked memory for the service.
- **`ExecStartPre`** waits until **`/dev/vfio/[0-9]*`** exists (bounded retries; avoids races after **qat.service** becomes active).

### Runtime limits for the **`haproxy`** user

**`/etc/security/limits.d/99-haproxy-qat.conf`** sets **`memlock`** to **`unlimited`** for **`haproxy`** (relevant when **`haproxy -c`** or the daemon runs as that user).

### Configuration validation

With QAT, HAProxy is stopped before **`haproxy -c`** as root (VFIO nodes cannot be held twice), then **`haproxy -c`** is run **as user `haproxy`** so the engine initialization path matches production.

---

## Verification checklist

| Check | Command / artifact |
|--------|---------------------|
| HAProxy has engine support | `haproxy -vv 2>&1 \| grep -i USE_ENGINE` |
| Marker present | `test -f /var/lib/qatbench/haproxy-use-engine-from-src` |
| Kernel | `grep intel_iommu /proc/cmdline`; **`vfio-pci.ids`** lists your QAT VF IDs |
| QAT userspace | `systemctl is-active qat.service` |
| VFIO nodes | `ls /dev/vfio/` |
| Config syntax | `haproxy -c -f /var/lib/haproxy/conf/haproxy.config` (role also validates as **`haproxy`**) |

---

## Ansible roles and files (quick map)

| Concern | Role | Key paths |
|---------|------|-----------|
| IOMMU / VFIO IDs / qatlib / qatengine | `ansible/roles/qat_prereqs` | `tasks/main.yml`, `tasks/kernel_cmdline.yml`, `defaults/main.yml` |
| SRPM rebuild `USE_ENGINE=1` | `ansible/roles/haproxy_qat_build` | `tasks/main.yml`, `tasks/source_repo_phase.yml`, `tasks/rebuild_context.yml`, `defaults/main.yml`, `README.md` |
| HAProxy config, systemd, SELinux, limits | `ansible/roles/haproxy_server` | `tasks/main.yml`, `templates/conf/haproxy.config.j2`, `templates/haproxy.service.d-qatbench.conf.j2`, `files/selinux/qatbench_haproxy_vfio.te` |
| Play order | `ansible/playbooks/deploy_benchmark.yml` | `enable_qat` gates QAT roles |

---

## Related documentation

- [HAPROXY_USE_ENGINE_BUILD.md](./HAPROXY_USE_ENGINE_BUILD.md) — manual SRPM procedure aligned with **`haproxy_qat_build`**.
- `ansible/roles/haproxy_qat_build/README.md` — variables, **`--start-at-task`** resume hint.

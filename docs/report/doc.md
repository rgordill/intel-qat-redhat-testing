# Intel QuickAssist: recent technology context

**What QAT is today.** Intel positions **QuickAssist Technology** as a mix of **hardware IP** (on-package accelerators on many Intel Xeon Scalable and **Intel Xeon 6** parts) and **software** (kernel drivers, user-space libraries, **OpenSSL QAT Engine**, compression plug-ins). A compact overview of scope—crypto, compression, and platform placement—is in Intel’s public **technology brief** ([PDF](https://cdrdv2-public.intel.com/784036/Intel%20QAT%20Technology%20Brief.pdf)).

**Generations and integration.** Recent materials emphasize **in-silicon QAT** on **4th and 5th Gen Intel Xeon Scalable** processors and on **Intel Xeon 6** products, reducing reliance on discrete PCIe QAT cards for many rack designs. Compression work has also moved forward: Intel has discussed **Zstandard (zstd)**-related offload via QAT-style plug-ins on newer Xeon generations (e.g. community and Intel posts on **compression with QAT** freeing CPU for other work—see [Intel Community blog](https://community.intel.com/t5/Blogs/Tech-Innovation/Data-Center/Data-Compression-with-Intel-QuickAssist-Technology-Frees-Up/post/1730284)).

**TLS and QUIC.** For edge and L7 stacks, the recurring theme in Intel-published studies is **offloading or accelerating TLS handshakes and bulk crypto** (and, separately, **QUIC**) so connection rates and power efficiency improve versus pure software crypto on the same silicon. The nginx white paper and QUIC acceleration PDF linked in the table above are representative; numbers are **vendor-reported** under specific software versions and should not be read as guarantees for this repository’s wrk scenarios.

**RHEL, CentOS Stream, and Fedora.** **RHEL** documents how to validate the hardware QAT stack (firmware, `qat` service, `qatlib` / `qatengine`—see the Red Hat article in the table above). **CentOS Stream 9** follows the same kernel and userspace **RPM** lineage as **RHEL 9** for QAT drivers and OpenSSL engine packages (see also Intel’s [QAT Engine install notes](https://github.com/intel/QAT_Engine/blob/master/docs/install.md) for **CentOS** / RHEL-style installs). **Fedora** publishes **qatlib** in the main distro ([Fedora Packages](https://packages.fedoraproject.org/pkgs/qatlib/qatlib)). This project standardizes on **RHEL 9.6 + HAProxy 2.8**; CentOS Stream and Fedora are adjacent options for toolchain checks without introducing Debian-family packages.

**Looking ahead.** Besides classic TLS, **post-quantum cryptography** (PQC) is an active area; early evaluations of QAT with **hash-based** PQC signatures appear in independent posts such as the Among Bytes article referenced above. For this benchmark, PQC is **out of scope** unless the toolchain and ciphers are explicitly configured later.

# Motivation

This project (**Intel QAT + HAProxy benchmark**, internal name `qatbench`) measures HTTP and HTTPS load through a stack that mirrors **OpenShift-style ingress routing**: a front HAProxy terminates or forwards TLS like the cluster router, with **nginx** backends. The benchmark answers:

- How does **plain HTTP** throughput compare to **edge TLS**, **TLS passthrough**, and **re-encrypt** paths under the same load tool and topology?
- How do results scale with **wrk** threads and connections (repeatable CSV-driven scenarios)?
- How can the same automation run **locally (libvirt)**, on **AWS EC2** (smoke to large metal for QAT-capable hardware), and optionally against a **real OpenShift** cluster using **Kubernetes Ingress** examples?

**Goals:** reproducible provisioning (Terraform + Ansible), comparable numbers across environments, and a path to evaluate **Intel QuickAssist Technology (QAT)** for crypto offload when enabled on supported hardware (`enable_qat: true` in `ansible/group_vars/all.yml`).

**Expected results (qualitative):** cleartext HTTP should show the highest requests per second; edge and passthrough TLS sit between HTTP and the heavier re-encrypt path; latency grows with TLS mode and load. Exact numbers depend on instance type, network path, and whether QAT is used.

# Hardware

The repository supports a staged footprint:

| Stage | Use case | Typical hardware |
|--------|-----------|------------------|
| **Libvirt (KVM)** | Laptop or lab host | Two RHEL guests from a **RHEL 9.6** KVM qcow2 base; default sizing in docs: **2 vCPU, 4 GiB RAM, 10 GiB disk** per VM, dedicated NAT network (`qemu:///system`). |
| **AWS** | Shared / remote runs | **VPC** with public and private subnets; two instances (client + server). Defaults use types such as **c7i.large** for smoke; **c7i.metal-24xl** is the documented target for **QAT**-capable bare metal. Root volume size and AMI are configurable (see `terraform/aws/variables.tf`). |
| **OpenShift** | Ingress parity tests | No project-managed worker nodes; tests hit **Ingress** hosts on an existing cluster (DNS under `*.apps.<cluster>`). |

Committed wrk samples include runs labeled **`provider: aws`** (OpenShift Ingress URLs) and **`provider: libvirt`** (expanded scenario grid against the same ingress-style hostnames).

# Operating System and Software

**Why RHEL 9.6?** The benchmark targets a single, supportable userspace: RHEL 9.6 KVM images for libvirt and RHEL 9 AMIs on AWS (`ansible/group_vars/all.yml` references a current RHEL 9.6 AMI example). Subscription-managed installs keep nginx, HAProxy, and dependencies aligned with what customers run on RHEL 9.

**Why HAProxy 2.8 (OCP 4.20 ingress / RHEL 9.6 parity)?** The server role pins **`haproxy-2.8*`** (`ansible/roles/haproxy_server/defaults/main.yml`) so the router-style config and TLS behavior match the **OpenShift 4.20 ingress** line on RHEL 9.6, making lab numbers more comparable to cluster ingress.

**Why nginx?** Nginx acts as a **simple, well-understood origin** behind HAProxy: HTTP and HTTPS backends on loopback, with certificates from the shared `certs` role. It is not the subject of the study; it provides stable upstream behavior for the router analogue.

**Why wrk?** The load client installs **wrk** from the getpagespeed Copr (with EPEL **luajit**) for a **high-performance, scriptable** HTTP/HTTPS load generator on RHEL 9. Scenarios are CSV-driven (`scripts/vm/scenarios.csv`) and append to `result.csv` / rendered markdown.

**Why libvirt?** **Fast, local iteration** without cloud cost: Terraform with **terraform-provider-libvirt** provisions two guests and static DHCP mappings; Ansible configures the full stack. Same playbooks apply after swapping inventory.

**Why AWS?** **Elastic capacity**: scale from small instances for smoke tests to **metal** instances where **Intel QAT** devices are available, using one codebase (`terraform/aws` + same Ansible).

**Why OpenShift?** To validate the **Kubernetes Ingress** manifests under `kubernetes/` and compare **cluster ingress** behavior to the **HAProxy-on-VM** router analogue—same TLS termination modes (HTTP / edge / passthrough / reencrypt) with different implementations.

# Architecture

- **Router analogue (VM benchmark):** A **bench-server** runs **BIND** (libvirt DNS for `*.apps.<domain>`), **PKI** (`certs`), **nginx** backends, and **HAProxy** with a vendor-style template (gomplate) mapping **four logical routes**: plain HTTP, edge TLS, TCP passthrough, and re-encrypt to nginx.
- **Client:** **bench-client** resolves the server, trusts the benchmark CA, and runs **wrk** against URLs in `scenarios.csv` (optionally over SSH via `scripts/vm/run-scenarios.sh`).
- **OpenShift path:** Manifests deploy nginx plus **Ingress** resources; `scripts/openshift/` substitutes `INGRESS_HOST`; wrk targets live cluster URLs instead of the VM HAProxy.

Traffic flow (VM mode): **wrk → HAProxy (TLS or TCP as per scenario) → nginx on loopback**.

# Deployment

1. **Infrastructure:** `scripts/vm/provision-infrastructure.sh libvirt` or `… aws` runs Terraform and `scripts/terraform/render-ansible-inventory.sh` to produce `ansible/inventory/hosts.auto.yml`.
2. **Configuration:** `ansible-playbook playbooks/terraform.yml` (with `-e provider=aws` when needed), then `ansible-playbook -i inventory/hosts.auto.yml playbooks/deploy_benchmark.yml` (or `scripts/vm/deploy_components.sh`).
3. **Tests:** `scripts/vm/run-scenarios.sh` executes the CSV matrix; `--list` prints the scenario table. OpenShift: set `INGRESS_HOST` and use `scripts/openshift/deploy-scenario.sh` / `deploy-and-test-all.sh`.

Optional: `scripts/vm/generate-scenarios.sh` expands `scenarios.template.yaml` into additional CSV rows. Results are summarized with `scripts/vm/render-results-md.sh` into `scripts/vm/result.md`.

# Scenarios

Scenarios are identified by **`id`** (e.g. `a-w4-x16`) and map to four **topologies**:

| Letter | Mode | Description (abbrev.) |
|--------|------|------------------------|
| **a** | Plain HTTP | Client HTTP → HAProxy HTTP → nginx HTTP |
| **b** | Edge TLS | Client HTTPS → HAProxy terminates TLS → nginx HTTP |
| **c** | Passthrough | Client HTTPS (SNI) → TCP mode → nginx HTTPS |
| **d** | Re-encrypt | Client HTTPS → HAProxy TLS → nginx HTTPS |

The generated table in `scripts/vm/scenarios.md` lists **wrk_threads**, **wrk_connections**, and **wrk_duration_sec** per row. A common smoke shape is **4 threads × 64 connections × 30 s** (see sample results below).

# Results

## Non-QAT results

Default configuration has **`enable_qat: false`** in `ansible/group_vars/all.yml`. The following are taken from committed artifacts in the repo (April 2026).

**A. OpenShift Ingress sample (`scripts/vm/result.md`)** — single smoke row per topology, **4 threads, 64 connections, 30 s**, provider **aws**:

| Scenario | Mode | Requests/sec (approx.) | Notes |
|----------|------|------------------------|--------|
| a | HTTP | ~71k | Highest throughput; cleartext end-to-end to the exposed route. |
| b | Edge TLS | ~5.8k | TLS at ingress; lower than HTTP as expected. |
| c | Passthrough | ~5.2k | TCP/SNI passthrough to backend TLS. |
| d | Re-encrypt | ~5.7k | Double TLS hop; latency higher than edge in this sample. |

**B. Libvirt expanded grid (`scripts/vm/result.low.csv`)** — same four topologies with **varying wrk threads (4 / 8 / 16) and connection multipliers** against `*.apps.sandbox963.opentlc.com`. Illustrative peaks from that run:

- **a** (HTTP): up to **~18.7k req/s** (`a-w16-x16`) under high concurrency; many rows in the **~4.5k–9k** range depending on thread/conn mix; some runs report **socket connect errors** under aggressive concurrency (documented in the CSV).
- **b** (edge): up to **~36k req/s** (`b-w16-x8` / `b-w16-x16`).
- **c** (passthrough): up to **~39.5k req/s** (`c-w16-x16`).
- **d** (re-encrypt): up to **~32.4k req/s** (`d-w16-x16`); generally lower than **b/c** at comparable scale due to extra TLS work.

These two datasets differ in **ingress implementation** (cluster router vs lab DNS to HAProxy) and **load matrix**; use them as **examples**, not as a strict A/B between OpenShift and VM.

## QAT results

**Intel QAT** offload is wired through **`qat_prereqs`** when **`enable_qat: true`** (after subscription and hardware support). The repository defaults **do not** include a separate **QAT-enabled** results table in `result.csv` / `result.low.csv`; runs on **QAT-capable metal** (e.g. **c7i.metal-24xl**) should be captured the same way (`run-scenarios.sh`) and checked in or pasted here after execution.

To record QAT vs non-QAT: keep **`enable_qat: false`** for baseline, re-deploy with **`enable_qat: true`** on supported hardware, repeat the same `scenario_id` rows, and diff **`requests_per_sec`** and latency columns.

# Related work and public benchmarks

Other published work uses **similar ingredients**—TLS termination or QUIC at the edge, **OpenSSL**-family crypto, **nginx** or **HAProxy**, and **wrk**-style or CPS-oriented load—but rarely the same four-mode matrix (HTTP / edge / passthrough / re-encrypt) on one lab stack. Treat the links below as **context**, not as direct numerical comparison to `qatbench` runs (different builds, cipher suites, instance types, and metrics).

| Focus | Source | Why it is relevant |
|--------|--------|---------------------|
| **nginx + QAT, TLS CPS and efficiency** | Intel, *Intel® QuickAssist Technology — NGINX Performance* white paper (Feb 2023) — [product page / download](https://www.intel.com/content/www/us/en/content-details/767645/intel-quickassist-technology-nginx-performance-white-paper.html) | TLS cryptographic acceleration through **nginx** and **OpenSSL**; discusses connections-per-second and performance-per-watt on Intel Xeon platforms with QAT. |
| **QUIC + QAT** | Intel, *IETF QUIC Acceleration using Intel® QuickAssist Technology* (PDF) — [Intel document repository](https://cdrdv2-public.intel.com/787600/IETF%20QUIC%20Acceleration%20using%20Intel%C2%AE%20QuickAssist%20Technology%20-Intel%20QAT.pdf) | User-space QUIC (e.g. with **BoringSSL**) and asynchronous offload; Intel-reported gains in connection-per-second versus default crypto paths on comparable hardware. |
| **TLS offload framework** | ACM PPoPP ’19: *QTLS: high-performance TLS asynchronous offload framework with Intel® QuickAssist technology* — [DOI 10.1145/3293883.3295705](https://dl.acm.org/doi/10.1145/3293883.3295705) | Peer-reviewed work on **asynchronous TLS** offload patterns with QAT; useful for understanding offload architecture, not for apples-to-apples RPS with this repo. |
| **Fedora: QAT user space (RPM)** | Fedora Packages: *qatlib* — [packages.fedoraproject.org](https://packages.fedoraproject.org/pkgs/qatlib/qatlib) | **qatlib**, **qatlib-service**, and related RPMs on Fedora track the same upstream stack used on **RHEL 9**; useful for lab hosts or CI on Fedora. Intel’s [qatlib installation](https://intel.github.io/quickassist/qatlib/install.html) applies across RPM-based installs. |
| **RHEL: ISA / multi-buffer crypto** | Red Hat Customer Portal: *Intel Multi-Buffer Cryptography Libraries on Red Hat Enterprise Linux* — [access.redhat.com solution](https://access.redhat.com/solutions/7074826) | Documents ISA-optimized software crypto paths on **RHEL 9+** (and related material) when comparing **hardware QAT** with high-throughput software implementations on Intel Xeon. |
| **RHEL / enterprise validation** | Red Hat, *Accelerated encryption with 4th Gen Intel® Xeon® Scalable processors* — [Red Hat Blog](https://www.redhat.com/en/blog/accelerated-encryption-4th-gen-intelr-xeonr-scalable-processors) | Positions QAT alongside software crypto on RHEL-class stacks; aligns with the report’s **RHEL 9.6** target. |
| **QAT stack on RHEL** | Red Hat Knowledgebase: *Ensuring that Intel® QuickAssist Technology stack is working correctly on RHEL* — [access.redhat.com article](https://access.redhat.com/articles/6376901) | Operational checklist (firmware, driver, service) for **hardware QAT** on RHEL—what must be true before `enable_qat: true` is meaningful. |
| **OpenSSL QAT Engine** | Intel Developer Guide: *Building Software Acceleration Features in the Intel® Quick Assist Technology (Intel® QAT) Engine for OpenSSL* — [intel.com developer article](https://www.intel.com/content/www/us/en/developer/articles/guide/building-software-acceleration-features-in-the-intel-qat-engine-for-openssl.html) | How the **QAT Engine** plugs into OpenSSL for asymmetric/symmetric offload; background for how applications (HAProxy, nginx) benefit when linked against accelerated OpenSSL builds. |
| **PQC + QAT (2025)** | Among Bytes, *Evaluating Intel QAT for Hash-Based Post-Quantum Signature Schemes* — [amongbytes.com](https://amongbytes.com/posts/20251129-qat-intro/20251129-qat-intro.html) | Independent write-up (late 2025) on experimental **post-quantum** signature paths and QAT—illustrates where the ecosystem is heading beyond classic RSA/ECDSA TLS. |

# Conclusion

The project delivers a **repeatable HAProxy + nginx benchmark** aligned with **OpenShift ingress TLS modes**, runnable on **libvirt**, **AWS**, or **OpenShift**. Committed **non-QAT** results show the expected ordering (HTTP fastest; TLS modes lower; re-encrypt among the costliest). **QAT** evaluation remains a matter of enabling **`enable_qat`** on appropriate **metal** instances and appending measured runs to the same scenario/result pipeline.

The **Related work** and **Recent technology context** sections above point to comparable public studies (nginx, QUIC, academic QTLS) and summarize where QuickAssist sits on current Intel platforms and **RHEL-family** Linux; they complement but do not replace project-specific `result.csv` / `result.md` numbers.

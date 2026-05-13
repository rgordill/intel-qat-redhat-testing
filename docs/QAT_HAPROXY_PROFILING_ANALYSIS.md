# HAProxy QAT Engine Profiling Analysis

Comparative profiling of HAProxy TLS termination with and without the Intel
QAT (QuickAssist Technology) hardware engine, collected on 2026-05-12.

## Test Environment

| Property | Value |
|---|---|
| Host | `bench-server.sandbox1131.opentlc.com` |
| Kernel | `5.14.0-570.94.1.el9_6.x86_64` (RHEL 9.6) |
| CPU | 96 logical cores, Intel Sapphire Rapids |
| HAProxy | 2.8.14-c23fe91 (tested with 48 and 6 worker threads) |
| OpenSSL | 3.5.1 (RHEL, `USE_ENGINE=1`) |
| QAT HW | 4 x Intel 4xxx Series QAT (`8086:4940`), 64 VFs via VFIO |
| qatengine | 1.9.0-1.el9 |
| qatlib | 24.09.0-1.el9 |
| qatmgr | `--policy=32` (32 VFs per PF) |
| Workload | Edge-terminated TLS 1.2 connections (session reuse 100 %) |

### Run Identifiers

#### 48 Threads (`nbthread 48`)

| Label | Archive | Timestamp | Description |
|---|---|---|---|
| **noqat-48** | `bench-server-latest-48-nonqat.tar.gz` | `run-20260512T151027Z` | qatengine NOT loaded; OpenSSL default provider only |
| **qat-48** | `bench-server-latest-48-qat.tar.gz` | `run-20260512T154227Z` | qatengine loaded; QAT HW **active** |

#### 6 Threads (`nbthread 6`)

| Label | Archive | Timestamp | Description |
|---|---|---|---|
| **noqat-6** | `bench-server-latest-6-noqat.tar.gz` | `run-20260512T161424Z` | qatengine NOT loaded; OpenSSL default provider only |
| **qat-6** | `bench-server-latest-6-qat.tar.gz` | `run-20260512T160958Z` | qatengine loaded; QAT HW **active** |

### QAT Hardware Status

The `openssl engine qatengine` CLI probe reports `[ unavailable ]` because
the probe process does not belong to the `qat` group. However, HAProxy
itself **does** have `qat` group membership (`Groups: 994`) and the QAT
hardware is confirmed active by interrupt counters:

| QAT Device | qat-48 Interrupts | qat-6 Interrupts |
|---|--:|--:|
| `qat0-ae-cluster` (e8:00.0) | 14,083 | 32,715 |
| `qat1-ae-cluster` (ed:00.0) | 13,435 | 32,063 |
| `qat2-ae-cluster` (f2:00.0) | 27,293 | 57,021 |
| `qat3-ae-cluster` (f7:00.0) | 27,469 | 57,338 |
| **Total** | **82,280** | **179,137** |

In the noqat baselines, these counters show only 35 idle interrupts each.
The 6-thread QAT run generates **2.2x more QAT interrupts** than the
48-thread run, because less time is wasted on lock contention and more
work actually reaches the hardware rings.

---

## 1. Throughput Summary

### 1.1 At 48 Threads

| Metric | noqat-48 | qat-48 | Delta |
|---|--:|--:|---|
| MaxConnRate (conn/s) | **63,197** | 51,253 | **-19 %** |
| ConnRate at snapshot | **62,832** | 35,500 | **-43 %** |
| MaxSslRate (SSL/s) | **31,608** | 25,590 | **-19 %** |
| SslRate at snapshot | **31,421** | 17,753 | **-44 %** |
| Idle % | 49 % | 68 % | +19 pp (threads blocked, not busy) |
| BytesOutRate (MB/s) | **88.5** | 50.0 | **-44 %** |
| SslFrontendMaxKeyRate | 49 | **99** | +102 % (QAT handles key ops) |
| BootTime (ms) | 21 | **5,532** | **263x slower** startup |

### 1.2 At 6 Threads

| Metric | noqat-6 | qat-6 | Delta |
|---|--:|--:|---|
| MaxConnRate (conn/s) | 38,257 | **39,475** | **+3.2 %** |
| ConnRate at snapshot | 37,336 | **39,145** | **+4.8 %** |
| MaxSslRate (SSL/s) | 19,130 | **19,746** | **+3.2 %** |
| SslRate at snapshot | 18,666 | **19,574** | **+4.9 %** |
| Idle % | 1 % | 2 % | Both CPU-saturated |
| BytesOutRate (MB/s) | 50.1 | **52.6** | **+5.0 %** |
| SslFrontendMaxKeyRate | 49 | 49 | Equal |
| BootTime (ms) | 11 | **5,523** | **502x slower** startup |

### 1.3 Cross-Comparison

| Configuration | MaxConnRate | MaxSslRate | Relative to best |
|---|--:|--:|---|
| **noqat-48** | **63,197** | **31,608** | **baseline (best)** |
| qat-48 | 51,253 | 25,590 | -19 % |
| **qat-6** | 39,475 | 19,746 | -38 % |
| noqat-6 | 38,257 | 19,130 | -39 % |

> **Key finding**: At 48 threads, QAT causes a 43-44 % throughput
> regression due to lock contention. At 6 threads, the contention
> disappears and **QAT provides a net 3-5 % throughput improvement**
> over software OpenSSL, confirming that the hardware offload works
> when the threading model allows it. However, even the best QAT
> configuration (6 threads) achieves only 62 % of the noqat-48 peak,
> because the bottleneck shifts from lock contention to having only
> 6 CPUs available.

---

## 2. CPU Micro-Architecture (`perf stat`, 15 s window)

### 2.1 At 48 Threads

| Counter | noqat-48 | qat-48 | Notes |
|---|--:|--:|---|
| CPUs utilized | **29.2** | 16.5 | QAT run saturates far fewer cores |
| Cycles | 1,253 B | 659 B | |
| Instructions | 1,181 B | 401 B | |
| **IPC** | **0.94** | **0.61** | **-35 %** efficiency |
| Context-switch rate | 31.9 K/s | **51.9 K/s** | +63 % |
| Backend bound | 49.4 % | **53.1 %** | More stalls waiting for data/locks |
| Core bound | **26.5 %** | 22.9 % | |
| Memory bound | 22.9 % | **30.2 %** | +32 % relative increase |
| Retiring | **19.7 %** | 12.2 % | Less useful work per cycle |

### 2.2 At 6 Threads

| Counter | noqat-6 | qat-6 | Notes |
|---|--:|--:|---|
| CPUs utilized | 5.95 | 5.96 | Both fully saturate 6 cores |
| Cycles | 337 B | 329 B | Comparable |
| Instructions | **588 B** | 381 B | QAT executes 35 % fewer instructions |
| **IPC** | **1.74** | **1.16** | **-33 %** (but still nearly 2x better than 48t) |
| Context-switch rate | **192 /s** | 3,386 /s | 18x more in QAT (async polling) |
| Backend bound | **28.3 %** | 32.1 % | Slightly more memory stalls |
| Core bound | **10.4 %** | 8.0 % | |
| Memory bound | **17.9 %** | 24.1 % | +35 % relative increase |
| Retiring | **30.2 %** | 20.3 % | QAT wastes more cycles |
| Frontend bound | 36.3 % | **41.0 %** | I-cache pressure from engine libraries |

### 2.3 IPC Scaling Analysis

| Config | IPC | Explanation |
|---|--:|---|
| noqat-6 | **1.74** | Best overall: tight code, no contention, no engine overhead |
| qat-6 | **1.16** | QAT engine library overhead reduces IPC but no spinlock collapse |
| noqat-48 | **0.94** | High thread count causes accept-path spinlock contention |
| qat-48 | **0.61** | Worst: both spinlock and futex contention compound |

At 6 threads, the qatengine still reduces IPC by 33 % due to additional
library code (`libqat.so`, `libusdm.so`, `qatengine.so`), ASYNC
job management, and extra `pthread_rwlock` operations. However, these
overheads no longer cause **contention** because 6 threads rarely collide
on the locks. The IPC penalty is compensated by the hardware offloading
actual crypto computation off the CPU.

---

## 3. Hot-Path Analysis (`perf report`, top symbols)

### 3.1 Kernel Spinlock Contention: The Thread-Scaling Wall

| Symbol | noqat-48 | qat-48 | noqat-6 | qat-6 |
|---|--:|--:|--:|--:|
| `native_queued_spin_lock_slowpath` | **24.98 %** | **24.08 %** | 0.09 % | 0.21 % |
| `_raw_spin_lock` | 0.88 % | 1.20 % | **1.41 %** | **1.65 %** |

At 48 threads, 25 % of all CPU cycles are burned spinning on kernel
locks. At 6 threads, this drops to **under 0.3 %** -- a **100x
reduction** -- confirming the contention is purely a function of thread
count, not QAT.

#### 48-Thread noqat Call-Chain (24.98 %)

| Weight | Lock primitive | Caller chain |
|---:|---|---|
| 13.56 % | `_raw_spin_lock_bh` | `lock_sock_nested` -> `inet_csk_accept` -> `accept4` |
| 9.62 % | `_raw_spin_lock_irqsave` | `__wake_up_sync_key` -> `unix_stream_connect` |
| 1.80 % | `_raw_spin_lock` | `alloc_fd` / `put_unused_fd` |

#### 48-Thread qat Call-Chain (24.08 %)

| Weight | Lock primitive | Caller chain |
|---:|---|---|
| 10.23 % | `_raw_spin_lock_bh` | `lock_sock_nested` -> `inet_csk_accept` |
| **7.59 %** | `_raw_spin_lock` | **`futex_q_lock` (3.41 %) + `futex_wake` (3.33 %)** -> qatengine HMAC locking |
| 6.25 % | `_raw_spin_lock_irqsave` | `__wake_up_sync_key` -> `unix_stream_connect` |

At 48 threads, 7.59 % of cycles are wasted on futex contention from
the qatengine's `pthread_rwlock_wrlock` around HMAC operations. At
6 threads, this futex contention **disappears entirely** from the
profile.

### 3.2 qatengine Locking: 48 vs 6 Threads

| Symbol | qat-48 | qat-6 | Notes |
|---|--:|--:|---|
| `pthread_rwlock_wrlock` | **2.22 %** | **1.44 %** | Present but not contended at 6t |
| `pthread_rwlock_unlock` | 1.11 % | **1.26 %** | Higher share at 6t (more actual unlocks vs spinning) |
| `pthread_rwlock_rdlock` | 0.49 % | **1.26 %** | More read-lock activity at 6t |
| `HMAC_Init_ex` (direct) | 0.41 % | **0.92 %** | 2x more visible: actually executing, not blocked |
| `0x1b54b0` / `0x1b6982` (HMAC internal) | 1.37 % | 0.92 % + 0.67 % | |
| `EVP_MD_get_block_size` | 0.82 % | 0.62 % | |
| `finish_task_switch` | 0.80 % | — | Gone at 6t: no futex-induced scheduling |
| `futex_wake` | 3.33 % | 0.11 % | **30x reduction** |
| `ASYNC_start_job` / `ASYNC_pause_job` | — | 0.11 % + 0.10 % | Async model visible at 6t |
| `libqat.so` functions | — | 0.11 % + 0.09 % + ... | QAT library code visible at 6t |
| `qatengine.so` (`qat_pkey_ecx_derive25519`) | — | 0.06 % | X25519 offloaded to QAT HW |

At 6 threads the same locking code is present but threads rarely
collide, so cycles are spent doing actual crypto work (higher `HMAC_Init_ex`
share) and QAT-specific functions (`libqat.so`, `ASYNC_*`) become
visible in the profile for the first time.

### 3.3 OpenSSL Crypto Functions (all configurations)

| Symbol | noqat-48 | qat-48 | noqat-6 | qat-6 |
|---|--:|--:|--:|--:|
| `EVP_MD_free` | 2.37 % | 1.74 % | **1.44 %** | **1.31 %** |
| `EVP_MD_up_ref` | 1.66 % | 1.76 % | **1.10 %** | **1.40 %** |
| `EVP_MD_CTX_copy_ex` | 1.01 % | 0.81 % | **0.71 %** | **0.77 %** |
| `EVP_DigestUpdate` | 0.75 % | 0.60 % | **0.48 %** | **0.45 %** |
| `OPENSSL_cleanse` | 0.65 % | 0.56 % | **1.24 %** | **1.27 %** |
| `HMAC_Init_ex` | 0.47 % | 0.41 % | **0.94 %** | **0.92 %** |
| `SHA256_Final` | 0.34 % | 0.25 % | **0.27 %** | **0.29 %** |

At 6 threads the relative weights of crypto functions increase because
spinlock contention no longer dominates the profile. The noqat-6 and
qat-6 profiles show very similar crypto overhead, confirming that at low
thread counts the qatengine's locking does not add measurable contention.

### 3.4 HAProxy Application Functions

| Symbol | noqat-48 | qat-48 | noqat-6 | qat-6 |
|---|--:|--:|--:|--:|
| `process_stream` | 0.42 % | 0.42 % | **0.52 %** | **0.64 %** |
| `listener_accept` | 0.40 % | 0.36 % | **0.29 %** | **0.35 %** |
| `run_tasks_from_lists` | 0.25 % | 0.21 % | **0.43 %** | **0.46 %** |
| `ssl_sock_io_cb` | 0.08 % | 0.10 % | **0.16 %** | **0.20 %** |

At 6 threads, application code is proportionally more visible because
the lock overhead no longer drowns it out.

---

## 4. Process-Level Impact

| Metric | noqat-48 | qat-48 | noqat-6 | qat-6 |
|---|--:|--:|--:|--:|
| VmRSS | 44 MB | **182 MB** | **22 MB** | **129 MB** |
| VmLck (locked) | 0 | 92 MB | 0 | **92 MB** |
| Threads | 48 | 49 | 6 | **7** |
| Groups | — | 994 (qat) | — | 994 (qat) |
| BootTime (ms) | 21 | 5,532 | 11 | **5,523** |
| FDSize | 512 | 1,024 | 256 | 256 |
| Context switches (vol) | 42,474 | 182,783 | **1,955** | **23,011** |
| Context switches (invol) | 55,990 | 10,291 | **11,141** | **3,558** |
| Tainted flag | 0 | 0x40 | 0 | 0x40 |

The QAT engine adds ~90 MB of locked DMA memory and ~100 MB RSS
regardless of thread count. The 5.5 s boot penalty is also constant.
The dramatic difference is in context switches: at 48 threads QAT
causes 182K voluntary switches (futex waits), but at 6 threads this
drops to 23K -- still higher than the 6-thread noqat baseline (2K) but
far less pathological.

---

## 5. Root Cause: qatengine Locking vs Thread Count

The qatengine wraps every HMAC operation in a **write lock**
(`pthread_rwlock_wrlock`). The impact depends entirely on how many
threads compete for that lock:

```
HAProxy thread (1 of N)
  └─ SSL_do_handshake / record processing
       └─ HMAC_Init_ex
            └─ qatengine internal path
                 ├─ CRYPTO_THREAD_write_lock (pthread_rwlock_wrlock)
                 │   └─ 48t: futex_wait → 3.41 % spinlock
                 │   └─  6t: uncontended → 0 % spinlock
                 ├─ QAT HW operation (offloaded to hardware ring)
                 ├─ qaeCryptoMemFreeNonZero (libusdm.so)
                 │   └─ 48t: futex contention 0.90 %
                 │   └─  6t: uncontended
                 └─ CRYPTO_THREAD_unlock (pthread_rwlock_unlock)
                     └─ 48t: futex_wake → 3.33 % spinlock
                     └─  6t: uncontended
```

### At 48 Threads (Net Negative)

- **Saved**: ~0.6 % reduction in crypto function overhead
- **Added**: ~6.6 % in futex contention, rwlock operations, scheduling
- **Net**: **~6 % wasted CPU**, translating to **43-44 % throughput loss**
- Root cause: 48 threads competing for a write lock creates severe
  serialization; threads spend more time waiting than computing

### At 6 Threads (Net Positive)

- **Saved**: CPU cycles for RSA/X25519/HMAC offloaded to QAT hardware
- **Added**: rwlock acquire/release overhead (~2.7 % total), ASYNC job
  management (~0.2 %), `libqat.so`/`libusdm.so` library code (~0.3 %)
- **Net**: **~3-5 % throughput gain** -- the hardware offload outweighs
  the (uncontended) locking overhead
- Root cause: 6 threads rarely collide on the write lock, so it acts
  as a fast uncontended atomic operation rather than a serialization point

---

## 6. Key Findings

1. **QAT provides a net benefit at 6 threads but is destructive at 48.**
   At `nbthread 6`, QAT delivers a 3-5 % throughput improvement over
   software OpenSSL (39.5K vs 38.3K conn/s). At `nbthread 48`, the
   same engine causes a 43-44 % throughput regression (35.5K vs 62.8K
   conn/s) due to lock contention.

2. **The qatengine's locking model has a sharp scaling cliff.** The
   `pthread_rwlock_wrlock` around HMAC operations is uncontended at 6
   threads (0.21 % spinlock overhead) but causes 24 % spinlock
   contention at 48 threads. The inflection point lies somewhere between
   6 and 48 threads.

3. **6-thread QAT generates 2.2x more hardware interrupts than 48-thread
   QAT.** With less lock contention, threads spend more time submitting
   work to QAT rings (179K vs 82K interrupts), proving the hardware is
   underutilized at high thread counts.

4. **IPC degrades with both QAT and thread count, but differently.**
   QAT library overhead reduces IPC by ~33 % regardless of threads
   (1.74 -> 1.16 at 6t; 0.94 -> 0.61 at 48t). Thread-count contention
   adds a further ~46 % IPC drop (1.74 at 6t vs 0.94 at 48t for noqat).

5. **Memory and boot-time costs are constant.** QAT adds ~92 MB locked
   DMA memory and 5.5 s boot overhead regardless of thread count. These
   are fixed costs that become proportionally less significant at higher
   throughput.

6. **noqat-48 remains the absolute throughput leader.** Even though
   qat-6 beats noqat-6, neither 6-thread configuration matches the
   noqat-48 peak of 63K conn/s. The optimal configuration requires
   finding the thread count where QAT offload still provides a net
   benefit while maximizing CPU parallelism.

---

## 7. Recommendations

### Find the Optimal Thread Count for QAT

The data shows QAT is beneficial at 6 threads but harmful at 48. Binary
search between 6 and 48 to find the crossover point where QAT's lock
contention starts to outweigh its hardware offload benefit:

```
# Suggested test points for haproxy.cfg:
global
    nbthread 12   # 2x current sweet spot
    nbthread 16   # Middle ground
    nbthread 24   # Half of 48
```

The goal is to find the highest thread count where `qat-N` still
outperforms `noqat-N`, then compare against `noqat-48` to determine the
absolute best configuration.

### Investigate qatengine Threading Model

The qatengine v1.9.0 wraps HMAC operations in `CRYPTO_THREAD_write_lock`.
Check if newer versions (or build-time options) support:
- Per-thread engine instances (one QAT ring per thread)
- Lock-free submission to hardware rings
- Read-locked or lockless HMAC paths

### Consider SO_REUSEPORT for the Accept Path

At 48 threads, `inet_csk_accept` spinlock contention accounts for
10-14 % of cycles. This is independent of QAT and affects the noqat
baseline as well. Using `SO_REUSEPORT` with separate listener sockets
per thread would eliminate this bottleneck and could significantly
improve the noqat-48 baseline.

### Evaluate Multi-Process Instead of Multi-Thread

Running multiple single-threaded (or few-threaded) HAProxy processes
with `SO_REUSEPORT` could provide both high parallelism and low lock
contention. Each process would have its own qatengine instance with
no cross-process locking.

### Match QAT VFs to Thread Count

With `--policy=32` the system exposes 64 VFs (16 per PF). Align the
VF count to the HAProxy thread count so each thread gets a dedicated
hardware ring, potentially eliminating the need for the write lock
entirely.

---

## Appendix: Data Sources

All data was collected by the `qatbench_observability` Ansible role.

### Archives

| Label | Archive | Run Timestamp |
|---|---|---|
| noqat-48 | `bench-server-latest-48-nonqat.tar.gz` | `run-20260512T151027Z` |
| qat-48 | `bench-server-latest-48-qat.tar.gz` | `run-20260512T154227Z` |
| noqat-6 | `bench-server-latest-6-noqat.tar.gz` | `run-20260512T161424Z` |
| qat-6 | `bench-server-latest-6-qat.tar.gz` | `run-20260512T160958Z` |

### Files per Run

| File | Content |
|---|---|
| `09-perf-stat.txt` | `perf stat` counters for 15 s on HAProxy PIDs |
| `09b-perf-report-snapshot.txt` | `perf report` with call-graph from a 15 s `perf record` snapshot |
| `01-host.txt` | System identification (kernel, OpenSSL, CPU) |
| `03-haproxy-binary.txt` | HAProxy build flags and loaded OpenSSL providers |
| `04-openssl-engine.txt` | `openssl engine` output (qatengine availability) |
| `05-qat-runtime.txt` | QAT service status, VFIO devices, PCI topology, interrupts |
| `06-haproxy-process.txt` | `/proc/<pid>/status`, `/proc/<pid>/sched`, memory maps |
| `07-haproxy-socket.txt` | HAProxy admin socket `show info`, `show pools`, `show stat` |
| `08-prometheus-scrape.txt` | Prometheus `/metrics` endpoint scrape |

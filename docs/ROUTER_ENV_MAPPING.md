# HAProxy config ↔ OpenShift Router template (`ROUTER_*` / `SSL_*`)

The OpenShift router uses a Go-rendered [haproxy-config.template](https://github.com/openshift/router/blob/master/images/router/haproxy/conf/haproxy-config.template). This benchmark’s **`files/conf/haproxy.config`** is derived from that style but checked in as a **static** file (not rendered by the upstream Go template).

## Deployed layout on the benchmark server

The `haproxy_server` role installs the **static** router-style config and supporting files under `/var/lib/haproxy` (not `/etc/haproxy/haproxy.cfg`).

| Path | Source in repo | Purpose |
|------|----------------|--------|
| `/var/lib/haproxy/conf/haproxy.config` | `ansible/roles/haproxy_server/files/conf/haproxy.config` | Main HAProxy config |
| `/var/lib/haproxy/conf/os_*.map` | `templates/conf/*.map.j2` (Jinja) | Route/map regex tables |
| `/var/lib/haproxy/conf/cert_config.map` | `templates/cert_config.map.j2` | `crt-list` host → PEM mapping |
| `/var/lib/haproxy/conf/error-page-*.http` | `files/conf/error-page-*.http` | Custom 503/404 bodies |
| `/var/lib/haproxy/router/certs/default.pem` | Copy of `{{ certs_role_dir }}/haproxy.pem` | Edge/SNI default certificate |
| `/var/lib/haproxy/router/cacerts/nginx.pem` | Copy of `{{ certs_role_dir }}/ca.crt` | CA for **re-encrypt** backend TLS verify (`ca-file` on `be_secure`) |
| `/var/lib/haproxy/run/haproxy.pid` | (runtime) | PID file |
| `/var/lib/haproxy/run/haproxy.sock` | (runtime) | Stats / master socket (`-x` matches this path) |

The **`certs`** role (runs before `haproxy_server` in `deploy_benchmark.yml`) generates `ca.crt`, server certs, and `haproxy.pem` under `cert_dir` (default `/etc/pki/qat-bench`). HAProxy copies the CA to `router/cacerts/nginx.pem` so the re-encrypt backend can verify nginx’s HTTPS certificate.

`ansible_managed` is set in `ansible/ansible.cfg` for templated files.

## systemd

A drop-in overrides `ExecStart` so the daemon matches the paths above, for example:

`/usr/sbin/haproxy -Ws -f /var/lib/haproxy/conf/haproxy.config -p /var/lib/haproxy/run/haproxy.pid -x /var/lib/haproxy/run/haproxy.sock`

See `ansible/roles/haproxy_server/templates/haproxy.service.d-qatbench.conf.j2` and `haproxy_systemd_exec_start_opts` in role defaults.

## Scenarios

| ID | Topology | Router analogue | Notes |
|----|----------|-----------------|-------|
| (a) | Client HTTP → HAProxy HTTP → nginx HTTP | Plain `be_http` / `public` frontend | No TLS |
| (b) | Client HTTPS → HAProxy TLS → nginx HTTP | **Edge** termination (`be_edge_http`) | Software OpenSSL |
| (c) | Same as (b) with `ssl-engine qatengine` when `qatbench_enable_qat` | Edge + hardware crypto | Only on `c7i.metal-24xl` after QAT gate |
| (d) | Client HTTPS → HAProxy TLS → nginx HTTPS (re-encrypt) | **Re-encrypt** (`be_secure`) | `verify` + CA under `router/cacerts/nginx.pem` |
| (e) | Same as (d) + QAT on frontend when enabled | Re-encrypt + QAT at edge | Metal + QAT |

## Environment variables (reference from upstream template)

These appear in the upstream **global** / **defaults** sections. Map them when tuning this bench to match router behaviour:

| Variable | Typical default in template | Use in this bench |
|----------|----------------------------|-------------------|
| `ROUTER_MAX_CONNECTIONS` | `50000` | `global maxconn` |
| `ROUTER_THREADS` | unset | `nbthread` (optional) |
| `SSL_MIN_VERSION` | `TLSv1.2` | OpenSSL / bind `ssl-min-ver` if you add explicit ssl-default-bind |
| `ROUTER_CIPHERS` | `intermediate` | `ssl-default-bind-ciphers` if you mirror Mozilla intermediate |
| `ROUTER_BUF_SIZE` / `ROUTER_MAX_REWRITE_SIZE` | `32768` / `8192` | `tune.bufsize` / `tune.maxrewrite` if needed |

Export them in a shell profile or `Environment=` drop-in for `haproxy.service` if you want parity experiments; the checked-in **static** `haproxy.config` sets a **minimal** global block focused on correctness and CPS.

## Reload

After changing scenario or vars: set `haproxy_scenario` in `ansible/group_vars/all.yml` (or `-e haproxy_scenario=b`) and re-run `playbooks/deploy_benchmark.yml`. The role validates with `haproxy -c -f /var/lib/haproxy/conf/haproxy.config` and restarts the service when files change. For a manual reload after editing files under `/var/lib/haproxy/conf/`, use `systemctl reload haproxy` (or `restart` if you change the systemd drop-in).

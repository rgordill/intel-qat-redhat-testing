# HAProxy config ↔ OpenShift Router template (`ROUTER_*` / `SSL_*`)

The OpenShift router uses a Go-rendered [haproxy-config.template](https://github.com/openshift/router/blob/master/images/router/haproxy/conf/haproxy-config.template). This project uses **scenario-equivalent** standalone `haproxy.cfg` fragments (Ansible template `roles/haproxy_benchmark/templates/haproxy.cfg.j2`).

## Scenarios

| ID | Topology | Router analogue | Notes |
|----|----------|-----------------|--------|
| (a) | Client HTTP → HAProxy HTTP → nginx HTTP | Plain `be_http` / `public` frontend | No TLS |
| (b) | Client HTTPS → HAProxy TLS → nginx HTTP | **Edge** termination (`be_edge_http`) | Software OpenSSL |
| (c) | Same as (b) with `ssl-engine qatengine` when `qatbench_enable_qat` | Edge + hardware crypto | Only on `c7i.metal-24xl` after QAT gate |
| (d) | Client HTTPS → HAProxy TLS → nginx HTTPS (re-encrypt) | **Re-encrypt** (`be_secure`) | `verify` + CA for backend |
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

Export them in a shell profile or `Environment=` drop-in for `haproxy.service` if you want parity experiments; the Ansible template currently sets a **minimal** global block focused on correctness and CPS.

## Reload

After changing scenario: set `haproxy_scenario` in `ansible/group_vars/all.yml` (or `-e haproxy_scenario=b`) and re-run `playbooks/deploy_benchmark.yml`, or `systemctl reload haproxy` on the server if you edit `/etc/haproxy/haproxy.cfg` by hand.

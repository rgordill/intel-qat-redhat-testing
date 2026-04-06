# Benchmark scenarios

Generated from [`scenarios.csv`](scenarios.csv) — refresh with `scripts/vm/render-scenarios-md.sh`.

| id | name | topology | router_analogue | target_url | wrk_run | wrk_threads | wrk_connections | wrk_duration_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| a | Plain HTTP | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| a-heavy | Plain HTTP (heavy) | Same as (a) with higher concurrency | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 16 | 256 | 30 |
| b | Edge TLS | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| b-heavy | Edge TLS (heavy) | Same as (b) with higher concurrency | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 16 | 256 | 30 |
| c | Passthrough | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| d | Re-encrypt | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |

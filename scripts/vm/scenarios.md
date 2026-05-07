# Benchmark scenarios

Generated from [`scenarios.csv`](scenarios.csv) — refresh with `scripts/vm/render-scenarios-md.sh`.

| id | name | topology | router_analogue | target_url | wrk_run | wrk_threads | wrk_connections | wrk_duration_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| a-w1-x1 | Plain HTTP (1T × 1×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 1 | 1 | 30 |
| a-w1-x2 | Plain HTTP (1T × 2×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 1 | 2 | 30 |
| a-w1-x4 | Plain HTTP (1T × 4×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 1 | 4 | 30 |
| a-w1-x8 | Plain HTTP (1T × 8×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 1 | 8 | 30 |
| a-w1-x16 | Plain HTTP (1T × 16×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 1 | 16 | 30 |
| a-w2-x1 | Plain HTTP (2T × 1×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 2 | 2 | 30 |
| a-w2-x2 | Plain HTTP (2T × 2×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 2 | 4 | 30 |
| a-w2-x4 | Plain HTTP (2T × 4×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 2 | 8 | 30 |
| a-w2-x8 | Plain HTTP (2T × 8×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 2 | 16 | 30 |
| a-w2-x16 | Plain HTTP (2T × 16×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 2 | 32 | 30 |
| a-w4-x1 | Plain HTTP (4T × 1×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 4 | 30 |
| a-w4-x2 | Plain HTTP (4T × 2×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 8 | 30 |
| a-w4-x4 | Plain HTTP (4T × 4×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 16 | 30 |
| a-w4-x8 | Plain HTTP (4T × 8×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 32 | 30 |
| a-w4-x16 | Plain HTTP (4T × 16×conn) | Client HTTP to HAProxy HTTP to nginx HTTP | Plain be_http / public | http://nginx-http.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| b-w1-x1 | Edge TLS (1T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 1 | 1 | 30 |
| b-w1-x2 | Edge TLS (1T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 1 | 2 | 30 |
| b-w1-x4 | Edge TLS (1T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 1 | 4 | 30 |
| b-w1-x8 | Edge TLS (1T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 1 | 8 | 30 |
| b-w1-x16 | Edge TLS (1T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 1 | 16 | 30 |
| b-w2-x1 | Edge TLS (2T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 2 | 2 | 30 |
| b-w2-x2 | Edge TLS (2T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 2 | 4 | 30 |
| b-w2-x4 | Edge TLS (2T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 2 | 8 | 30 |
| b-w2-x8 | Edge TLS (2T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 2 | 16 | 30 |
| b-w2-x16 | Edge TLS (2T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 2 | 32 | 30 |
| b-w4-x1 | Edge TLS (4T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 4 | 30 |
| b-w4-x2 | Edge TLS (4T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 8 | 30 |
| b-w4-x4 | Edge TLS (4T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 16 | 30 |
| b-w4-x8 | Edge TLS (4T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 32 | 30 |
| b-w4-x16 | Edge TLS (4T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTP | Edge termination be_edge_http | https://nginx-edge.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| c-w1-x1 | Passthrough (1T × 1×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 1 | 1 | 30 |
| c-w1-x2 | Passthrough (1T × 2×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 1 | 2 | 30 |
| c-w1-x4 | Passthrough (1T × 4×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 1 | 4 | 30 |
| c-w1-x8 | Passthrough (1T × 8×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 1 | 8 | 30 |
| c-w1-x16 | Passthrough (1T × 16×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 1 | 16 | 30 |
| c-w2-x1 | Passthrough (2T × 1×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 2 | 2 | 30 |
| c-w2-x2 | Passthrough (2T × 2×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 2 | 4 | 30 |
| c-w2-x4 | Passthrough (2T × 4×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 2 | 8 | 30 |
| c-w2-x8 | Passthrough (2T × 8×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 2 | 16 | 30 |
| c-w2-x16 | Passthrough (2T × 16×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 2 | 32 | 30 |
| c-w4-x1 | Passthrough (4T × 1×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 4 | 30 |
| c-w4-x2 | Passthrough (4T × 2×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 8 | 30 |
| c-w4-x4 | Passthrough (4T × 4×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 16 | 30 |
| c-w4-x8 | Passthrough (4T × 8×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 32 | 30 |
| c-w4-x16 | Passthrough (4T × 16×conn) | Client HTTPS (SNI) TCP passthrough to nginx HTTPS | be_tcp / public_ssl SNI map | https://nginx-passthrough.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |
| d-w1-x1 | Re-encrypt (1T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 1 | 1 | 30 |
| d-w1-x2 | Re-encrypt (1T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 1 | 2 | 30 |
| d-w1-x4 | Re-encrypt (1T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 1 | 4 | 30 |
| d-w1-x8 | Re-encrypt (1T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 1 | 8 | 30 |
| d-w1-x16 | Re-encrypt (1T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 1 | 16 | 30 |
| d-w2-x1 | Re-encrypt (2T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 2 | 2 | 30 |
| d-w2-x2 | Re-encrypt (2T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 2 | 4 | 30 |
| d-w2-x4 | Re-encrypt (2T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 2 | 8 | 30 |
| d-w2-x8 | Re-encrypt (2T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 2 | 16 | 30 |
| d-w2-x16 | Re-encrypt (2T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 2 | 32 | 30 |
| d-w4-x1 | Re-encrypt (4T × 1×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 4 | 30 |
| d-w4-x2 | Re-encrypt (4T × 2×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 8 | 30 |
| d-w4-x4 | Re-encrypt (4T × 4×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 16 | 30 |
| d-w4-x8 | Re-encrypt (4T × 8×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 32 | 30 |
| d-w4-x16 | Re-encrypt (4T × 16×conn) | Client HTTPS to HAProxy TLS to nginx HTTPS | Re-encrypt be_secure | https://nginx-reencrypt.apps.<qatbench_vm_domain>/ | 1 | 4 | 64 | 30 |

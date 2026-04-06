# Benchmark results

Generated from [`result.csv`](result.csv) — refresh with `scripts/vm/render-results-md.sh`.

| timestamp_utc | scenario_id | target_url | provider | wrk_run | wrk_threads | wrk_connections | wrk_duration_sec | requests_per_sec | transfer_per_sec | total_requests | wrk_actual_sec | latency_avg_ms | latency_stdev_ms | latency_max_ms | socket_errors | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-04-06T08:14:23Z | a | http://nginx-http.apps.atik.demo/ | libvirt | 1 | 4 | 64 | 30 | 6631.51 | 1.64MB | 199475 | 30.08 | 6.46ms | 7.19ms | 76.27ms | ok |  |
| 2026-04-06T08:14:56Z | a-heavy | http://nginx-http.apps.atik.demo/ | libvirt | 1 | 16 | 256 | 30 | 1766.80 | 448.60KB | 53191 | 30.11 | 64.69ms | 39.40ms | 177.51ms | ok |  |
| 2026-04-06T08:15:28Z | b | https://nginx-edge.apps.atik.demo/ | libvirt | 1 | 4 | 64 | 30 | 2979.85 | 823.53KB | 89570 | 30.06 | 11.13ms | 10.14ms | 296.98ms | ok |  |
| 2026-04-06T08:16:01Z | b-heavy | https://nginx-edge.apps.atik.demo/ | libvirt | 1 | 16 | 256 | 30 | 3066.53 | 847.49KB | 92298 | 30.10 | 38.86ms | 39.98ms | 1.01s | ok |  |
| 2026-04-06T08:16:34Z | c | https://nginx-passthrough.apps.atik.demo/ | libvirt | 1 | 4 | 64 | 30 | 2761.40 | 439.56KB | 83075 | 30.08 | 2.57ms | 2.45ms | 30.34ms | ok |  |
| 2026-04-06T08:17:06Z | d | https://nginx-reencrypt.apps.atik.demo/ | libvirt | 1 | 4 | 64 | 30 | 1422.97 | 393.26KB | 42801 | 30.08 | 34.01ms | 16.03ms | 366.87ms | ok |  |

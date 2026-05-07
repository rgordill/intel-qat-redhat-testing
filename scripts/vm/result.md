# Benchmark results

Generated from [`result.csv`](result.csv) — refresh with `scripts/vm/render-results-md.sh`.

| timestamp_utc | scenario_id | target_url | provider | wrk_run | wrk_threads | wrk_connections | wrk_duration_sec | requests_per_sec | transfer_per_sec | total_requests | wrk_actual_sec | latency_avg_ms | latency_stdev_ms | latency_max_ms | socket_errors | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-04-07T07:24:03Z | a | http://nginx-http.apps.sandbox963.opentlc.com/ | aws | 1 | 4 | 64 | 30 | 71358.84 | 17.69MB | 2141593 | 30.01 | 574.95us | 1.87ms | 213.25ms | ok |  |
| 2026-04-07T07:26:47Z | b | https://nginx-edge.apps.sandbox963.opentlc.com/ | aws | 1 | 4 | 64 | 30 | 5844.21 | 1.58MB | 175816 | 30.08 | 2.55ms | 2.22ms | 20.18ms | ok |  |
| 2026-04-07T07:29:31Z | c | https://nginx-passthrough.apps.sandbox963.opentlc.com/ | aws | 1 | 4 | 64 | 30 | 5170.17 | 822.99KB | 155530 | 30.08 | 2.98ms | 2.39ms | 22.87ms | ok |  |
| 2026-04-07T07:32:15Z | d | https://nginx-reencrypt.apps.sandbox963.opentlc.com/ | aws | 1 | 4 | 64 | 30 | 5662.77 | 1.53MB | 170236 | 30.06 | 4.61ms | 3.08ms | 61.19ms | ok |  |

# Monitoring Guide

What is measured, where it comes from, and how to read it.

## 1. What is monitored

| Area | Metric | Source | Collected by |
|---|---|---|---|
| **CPU** | `compute.googleapis.com/instance/cpu/utilization` (0-1) | Hypervisor | Built in, no agent needed |
| **Memory** | `agent.googleapis.com/memory/percent_used` (state = used) | Inside the VM | Ops Agent |
| **Storage** | `agent.googleapis.com/disk/percent_used` (state = used) | Inside the VM | Ops Agent |
| **Storage I/O** | `compute.googleapis.com/instance/disk/write_bytes_count` | Hypervisor | Built in |
| **Network** | `.../network/sent_bytes_count`, `.../received_bytes_count` | Hypervisor | Built in |
| **Network detail** | VPC flow logs (sampled 50%) | Subnet | Cloud Logging |
| **Application: traffic** | `logging.googleapis.com/user/<stack>_app_requests` | App JSON log | Ops Agent + log-based metric |
| **Application: errors** | `logging.googleapis.com/user/<stack>_app_errors` (HTTP 5xx) | App JSON log | Ops Agent + log-based metric |
| **Application: latency** | `logging.googleapis.com/user/<stack>_app_latency_ms` (distribution) | App JSON log | Ops Agent + log-based metric |
| **Availability** | `monitoring.googleapis.com/uptime_check/check_passed` | Global probes of `/healthz` | Uptime checks |

The **Ops Agent** is installed on every VM by the startup script. It is what makes memory, disk and application logs visible; without it only hypervisor metrics (CPU, network, disk I/O) exist.

## 2. How application metrics work

The demo app writes one JSON line per request:

```json
{"time": "2026-11-01T10:15:02+00:00", "instance": "cloudmon-dev-web-1", "method": "GET", "path": "/", "status": 200, "latency_ms": 3.2}
```

The Ops Agent ships the file to Cloud Logging (`parse_json` makes every field searchable as `jsonPayload.*`). Three **log-based metrics** then turn the log into numbers: a request counter, a 5xx counter, and a latency distribution (so you can chart p50 and p95, not just an average). The query string is never logged, so tokens do not leak into logs.

## 3. The dashboard

`terraform output dashboard_url` opens it. It has a guide panel and eleven charts:

| Row | Charts |
|---|---|
| 1 | CPU utilization, Memory used |
| 2 | Disk space used, Disk write throughput |
| 3 | Network sent, Network received |
| 4 | Requests per minute, Server errors per minute |
| 5 | Latency p50, Latency p95 |
| 6 | Health checks passing |

Every chart shows one line per VM, so a single misbehaving server stands out. Healthy ranges: CPU below 70%, memory below 85%, disk below 80%, p95 latency below 500 ms, health checks at 1.0.

## 4. Logs

In **Logging > Logs Explorer** useful queries:

```text
logName="projects/PROJECT/logs/demo_app"                          # all app requests
logName="projects/PROJECT/logs/demo_app" jsonPayload.status>=500    # failing requests
logName="projects/PROJECT/logs/demo_app" jsonPayload.latency_ms>500 # slow requests
```

## 5. Alerts and notifications

Eleven alert policies watch these metrics (see [ALERT_POLICIES.md](ALERT_POLICIES.md)). They notify the email addresses in `alert_emails`. In the console: **Monitoring > Alerting** shows open incidents and policy history.

## 6. Reading a performance report

`scripts/optimization-report.ps1` reads real utilization from the Monitoring API and writes `reports/performance-report.md`: average, p95 and max CPU, average and p95 memory, and a right-sizing verdict per VM. Use p95, not the average: the average hides the busy periods that users actually feel.

## 7. Cost of monitoring itself

Standard GCE metrics, Ops Agent metrics, uptime checks (first million executions per month) and a small log volume are free or nearly free at this scale. Costs grow with log volume (ingested GB) and with custom or high-cardinality metrics. Keep logs lean and avoid logging request bodies.

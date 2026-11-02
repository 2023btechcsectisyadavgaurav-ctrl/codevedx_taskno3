# Alert Policies

Eleven policies, tiered so people hear about a problem **before** it becomes an outage. Every policy contains its own runbook, so the notification email tells the responder what to do.

## Severity tiers

| Tier | Meaning | Expected response |
|---|---|---|
| **WARNING** | Early signal; users are not affected yet | Look during working hours |
| **ERROR** | Users may be affected | Act soon |
| **CRITICAL** | Outage or imminent outage | Act now |

## Policies

| # | Policy | Tier | Fires when | Default threshold | First action |
|---|---|---|---|---|---|
| 1 | CPU utilization above 70% | WARNING | Per-VM mean CPU stays above the threshold for the alert duration | 70% | Check traffic, look for runaway processes, plan capacity |
| 2 | CPU utilization above 90% | CRITICAL | Per-VM CPU saturated | 90% | Add capacity or shed load immediately |
| 3 | Memory used above 85% | ERROR | RAM nearly exhausted (OOM risk) | 85% | Find the leaking process, restart or resize |
| 4 | Disk space used above 80% | ERROR | A disk is filling up | 80% | Clean logs/temp files or grow the disk |
| 5 | Outbound network above 20 MB/s | WARNING | Unusual traffic or possible data exfiltration | 20 MB/s | Compare with request rate, check VPC flow logs |
| 6 | p95 request latency above 500 ms | ERROR | The slowest 5% of requests are too slow | 500 ms | Check CPU/memory, find slow paths in the log |
| 7 | More than 5 server errors in 5 minutes | CRITICAL | HTTP 5xx responses | 5 errors / 5 min | Read failing paths, roll back a bad change |
| 8 | VM over-provisioned: CPU below 5% for 6 h | WARNING | Cost optimization signal | 5% for 6 h | Run the right-sizing report, downsize or schedule |
| 9, 10 | Website down (one per web server) | CRITICAL | Health check fails from more than one probe location | 2+ locations | Check VM status and the app log |
| 11 | VM stopped reporting | CRITICAL | No uptime metric for 5 minutes | 5 min | Check instance status, start or recreate it |

All thresholds are Terraform variables (`cpu_warning_threshold`, `memory_threshold_percent`, `latency_threshold_ms`, ...). Validation rules prevent nonsense, for example a critical CPU threshold lower than the warning one.

## Why these alerts are accurate

- **Duration, not spikes.** A condition must hold for `alert_duration_seconds` (default 120 s; use 300 s or more in production) so a one-second blip does not page anyone.
- **Per-VM evaluation.** CPU, memory and disk are evaluated per instance, so one bad server is not hidden by healthy ones.
- **Percentiles for latency.** p95 shows what slow users experience; an average would hide it.
- **Multi-location uptime.** Availability fires only when the check fails from more than one location, which filters out a single probe's network hiccup.
- **Auto-close.** Incidents close automatically 30 minutes after the condition clears.

## Why they are proactive

- CPU has a **warning** tier at 70% well before the **critical** tier at 90%.
- Disk and memory alert at 80-85%, leaving room to act before exhaustion.
- The optimization alert catches waste before the bill does.

## Notifications

Email channels are created from `alert_emails`. A new email address may need to confirm in Google Cloud before it receives alerts; check **Monitoring > Alerting > Edit notification channels**. Slack, SMS, PagerDuty and Pub/Sub channels can be added to the same policies without changing the conditions.

## Testing the alerts

`scripts/generate-load.ps1` creates real load: CPU burn, slow requests and server errors (and, separately, memory pressure). Watch the dashboard climb, then Monitoring > Alerting for incidents, and your inbox for the runbook email. Incidents close on their own after the load stops.

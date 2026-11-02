# Optimization Playbook

How to use the monitoring data to make the system faster and cheaper. The rule: **measure, change one thing, measure again.**

## 1. Right-size compute

| Signal (use p95 over at least a week) | Action |
|---|---|
| CPU p95 < 20% **and** memory p95 < 50% | **Over-sized:** move to a smaller machine type (e.g. e2-medium → e2-small) |
| CPU p95 between 20% and 75%, memory p95 < 80% | **Well-sized:** leave it |
| CPU p95 > 75% **or** memory p95 > 80% | **Under-sized:** larger machine type, or add instances behind a load balancer |

Run `scripts/optimization-report.ps1 -Hours 24` (or a week) for this table with your real numbers. Google's own **Recommender** (`gcloud recommender ...`, also shown in the console under *Compute Engine > VM instances > Recommendations*) gives machine-type and idle-VM suggestions after about a day of data; the script prints them when available.

Match the **memory-to-CPU ratio** to the workload: memory-hungry apps with idle CPU fit high-memory types, not bigger general-purpose ones. A custom machine type avoids paying for resources you do not use.

## 2. Stop paying for idle resources

- **Idle VMs:** the `underutilized` alert flags VMs with almost no CPU for hours. Delete them, or stop them outside working hours (an instance schedule can start and stop VMs automatically).
- **Unattached disks and unused static IPs** cost money while doing nothing; list them with `gcloud compute disks list --filter="-users:*"` and `gcloud compute addresses list --filter="status=RESERVED"`.
- **Dev and test environments** rarely need to run overnight or at weekends.

## 3. Cut discounts into the bill

| Option | Saves | Use when |
|---|---|---|
| **Committed use discounts** (1 or 3 years) | Up to ~50%+ | Steady, predictable baseline load |
| **Sustained use discounts** | Automatic for long-running VMs | Nothing to do |
| **Spot VMs** | Large discount | Fault-tolerant batch or stateless work that can be interrupted |

## 4. Improve performance

| Symptom on the dashboard | Likely cause | Fix |
|---|---|---|
| CPU high and latency high together | CPU-bound app | Optimize the hot code path, scale out, or use a larger type |
| Latency high but CPU/memory low | Waiting on something slow (database, external API, disk) | Cache results, add indexes, parallelize calls, check disk I/O chart |
| Memory climbing steadily, never falling | Memory leak | Fix the leak; restart as a stop-gap |
| Errors rise with traffic | Capacity limit | Autoscaling (managed instance group + load balancer) |
| Disk write throughput saturated | Slow disk type | Use a faster disk type (pd-ssd / hyperdisk) or reduce writes |
| Network sent far above request volume | Large responses or unexpected transfers | Compress responses, use a CDN, check VPC flow logs |

## 5. Autoscale instead of over-provisioning

Provisioning for the peak wastes money 90% of the time. A managed instance group with an autoscaler (target CPU 60%) adds instances in a spike and removes them afterwards, so you pay for what you use. Project 1 in this series demonstrates exactly that pattern.

## 6. Keep monitoring lean

- Log what you will search for, not everything; log volume is the main monitoring cost.
- Add exclusion filters for noisy, low-value logs.
- Avoid high-cardinality metric labels (user IDs, request IDs).
- Review alert policies quarterly: delete the ones nobody acts on.

## 7. Review rhythm

| When | What |
|---|---|
| Daily | Open incidents; dashboard glance |
| Weekly | Performance report; right-sizing verdicts; idle resources |
| Monthly | Billing breakdown; committed-use review |
| Quarterly | Alert thresholds and runbooks; load test with `scripts/generate-load.ps1` |

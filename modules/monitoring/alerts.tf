# Alert policies, tiered so administrators hear about problems BEFORE they become outages:
#   WARNING  = early signal, act during working hours
#   ERROR    = users may be affected, act soon
#   CRITICAL = outage or imminent outage, act now
# Each policy carries its own runbook in the notification (documentation block).

locals {
  duration = var.alert_duration_seconds
  minutes  = floor(var.alert_duration_seconds / 60)

  # Threshold alerts are data-driven: one entry per policy, one resource block below.
  threshold_alerts = {
    cpu_warning = {
      area       = "cpu"
      severity   = "WARNING"
      title      = "CPU utilization above ${format("%.0f", var.cpu_warning_threshold * 100)}%"
      filter     = "metric.type=\"${local.cpu_metric}\" AND ${local.gce_scope}"
      aligner    = "ALIGN_MEAN"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.cpu_warning_threshold
      duration   = local.duration
      doc        = <<-EOT
        **Early warning:** CPU has been above ${format("%.0f", var.cpu_warning_threshold * 100)}% for ${local.minutes}+ minutes.

        1. Open the dashboard and check whether traffic (request rate) rose with CPU.
        2. If traffic is normal, look for a runaway process: `top` over IAP SSH.
        3. If load is real and sustained, plan capacity: a larger machine type or more instances.
        See docs/OPTIMIZATION_PLAYBOOK.md.
      EOT
    }

    cpu_critical = {
      area       = "cpu"
      severity   = "CRITICAL"
      title      = "CPU utilization above ${format("%.0f", var.cpu_critical_threshold * 100)}%"
      filter     = "metric.type=\"${local.cpu_metric}\" AND ${local.gce_scope}"
      aligner    = "ALIGN_MEAN"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.cpu_critical_threshold
      duration   = local.duration
      doc        = <<-EOT
        **Critical:** CPU is saturated (above ${format("%.0f", var.cpu_critical_threshold * 100)}% for ${local.minutes}+ minutes). Requests are likely slow or failing.

        1. Check the latency and error charts on the dashboard.
        2. Shed load or add capacity now (resize or add an instance).
        3. Find the cause afterwards: deployment, traffic spike or runaway process.
      EOT
    }

    memory_high = {
      area       = "memory"
      severity   = "ERROR"
      title      = "Memory used above ${var.memory_threshold_percent}%"
      filter     = "metric.type=\"${local.memory_metric}\" AND metric.labels.state=\"used\" AND ${local.gce_scope}"
      aligner    = "ALIGN_MEAN"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.memory_threshold_percent
      duration   = local.duration
      doc        = <<-EOT
        **Memory pressure:** more than ${var.memory_threshold_percent}% of RAM is in use for ${local.minutes}+ minutes. The kernel may start killing processes (out-of-memory).

        1. Over IAP SSH run `free -m` and `ps aux --sort=-%mem | head`.
        2. Restart a leaking process or move to a machine type with more memory.
        3. Memory is only visible because the Ops Agent is installed on the VM.
      EOT
    }

    disk_high = {
      area       = "storage"
      severity   = "ERROR"
      title      = "Disk space used above ${var.disk_threshold_percent}%"
      filter     = "metric.type=\"${local.disk_metric}\" AND metric.labels.state=\"used\" AND ${local.gce_scope}"
      aligner    = "ALIGN_MEAN"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.disk_threshold_percent
      duration   = local.duration
      doc        = <<-EOT
        **Disk filling up:** more than ${var.disk_threshold_percent}% of a disk is used.

        1. Over IAP SSH run `df -h` and `sudo du -xh / | sort -h | tail`.
        2. Remove old logs or temporary files, or grow the disk (`gcloud compute disks resize`).
      EOT
    }

    network_high = {
      area       = "network"
      severity   = "WARNING"
      title      = "Outbound network above ${var.network_threshold_mbps} MB/s"
      filter     = "metric.type=\"${local.net_sent_metric}\" AND ${local.gce_scope}"
      aligner    = "ALIGN_RATE"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.network_threshold_mbps * 1000000
      duration   = local.duration
      doc        = <<-EOT
        **Unusual outbound traffic:** a VM is sending more than ${var.network_threshold_mbps} MB/s for ${local.minutes}+ minutes. This can mean a traffic spike, a large download, or data exfiltration.

        1. Compare with the request-rate chart.
        2. Check VPC flow logs (Logging, `compute.googleapis.com/vpc_flows`) for the top destinations.
      EOT
    }

    latency_high = {
      area       = "application"
      severity   = "ERROR"
      title      = "p95 request latency above ${var.latency_threshold_ms} ms"
      filter     = "metric.type=\"${local.latency_metric}\" AND ${local.log_scope}"
      aligner    = "ALIGN_PERCENTILE_95"
      reducer    = ""
      period     = 60
      comparison = "COMPARISON_GT"
      threshold  = var.latency_threshold_ms
      duration   = local.duration
      doc        = <<-EOT
        **Slow application:** the 95th percentile request latency is above ${var.latency_threshold_ms} ms for ${local.minutes}+ minutes.

        1. Compare with CPU and memory: resource saturation is the usual cause.
        2. Search the app log in Logging for the slowest paths (`jsonPayload.latency_ms > 500`).
        3. Scale out, or fix the slow code path.
      EOT
    }

    errors_high = {
      area       = "application"
      severity   = "CRITICAL"
      title      = "More than ${var.error_threshold_count} server errors in 5 minutes"
      filter     = "metric.type=\"${local.errors_metric}\" AND ${local.log_scope}"
      aligner    = "ALIGN_SUM"
      reducer    = "REDUCE_SUM"
      period     = 300
      comparison = "COMPARISON_GT"
      threshold  = var.error_threshold_count
      duration   = 0
      doc        = <<-EOT
        **Server errors:** more than ${var.error_threshold_count} HTTP 5xx responses in 5 minutes.

        1. In Logging filter `jsonPayload.status>=500` to see which path fails.
        2. Check whether a deployment or a dependency change preceded the errors; roll back if so.
      EOT
    }

    underutilized = {
      area       = "optimization"
      severity   = "WARNING"
      title      = "VM over-provisioned: CPU below ${format("%.0f", var.underutilized_cpu_threshold * 100)}% for ${var.underutilized_hours}h"
      filter     = "metric.type=\"${local.cpu_metric}\" AND ${local.gce_scope}"
      aligner    = "ALIGN_MEAN"
      reducer    = ""
      period     = 3600
      comparison = "COMPARISON_LT"
      threshold  = var.underutilized_cpu_threshold
      duration   = var.underutilized_hours * 3600
      doc        = <<-EOT
        **Cost optimization:** a VM has used under ${format("%.0f", var.underutilized_cpu_threshold * 100)}% CPU for ${var.underutilized_hours} hours. It is probably bigger than it needs to be.

        1. Run `scripts/optimization-report.ps1` for a right-sizing recommendation.
        2. Downsize the machine type, schedule it to stop outside working hours, or delete it if unused.
        See docs/OPTIMIZATION_PLAYBOOK.md.
      EOT
    }
  }
}

resource "google_monitoring_alert_policy" "threshold" {
  for_each = local.threshold_alerts

  project               = var.project_id
  display_name          = "[${each.value.severity}] ${var.name} | ${each.value.title}"
  combiner              = "OR"
  severity              = each.value.severity
  notification_channels = local.channel_ids

  user_labels = {
    area  = each.value.area
    tier  = lower(each.value.severity)
    stack = var.stack_label
  }

  conditions {
    display_name = each.value.title

    condition_threshold {
      filter          = each.value.filter
      comparison      = each.value.comparison
      threshold_value = each.value.threshold
      duration        = "${each.value.duration}s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "${each.value.period}s"
        per_series_aligner   = each.value.aligner
        cross_series_reducer = each.value.reducer == "" ? null : each.value.reducer
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = each.value.doc
    mime_type = "text/markdown"
  }

  depends_on = [
    google_logging_metric.app_requests,
    google_logging_metric.app_errors,
    google_logging_metric.app_latency,
  ]
}

# Availability: alert when the health check fails from more than one probe location.
resource "google_monitoring_alert_policy" "uptime" {
  for_each = google_monitoring_uptime_check_config.web

  project               = var.project_id
  display_name          = "[CRITICAL] ${var.name} | Website down (${each.key})"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.channel_ids

  user_labels = {
    area  = "availability"
    tier  = "critical"
    stack = var.stack_label
  }

  conditions {
    display_name = "Uptime check failing from multiple locations"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${each.value.uptime_check_id}\" AND resource.type=\"uptime_url\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.*"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = <<-EOT
      **Website down:** the HTTP health check of ${each.key} is failing from more than one probe location.

      1. Open the URL in a browser and check the instance status in Compute Engine.
      2. If the VM is running, read the app log: `sudo journalctl -u demo-app -n 50` over IAP SSH.
      3. Restart the service (`sudo systemctl restart demo-app`) or recreate the VM.
    EOT
    mime_type = "text/markdown"
  }
}

# Availability: a VM that stops reporting at all (stopped, deleted, or crashed).
resource "google_monitoring_alert_policy" "instance_down" {
  project               = var.project_id
  display_name          = "[CRITICAL] ${var.name} | VM stopped reporting"
  combiner              = "OR"
  severity              = "CRITICAL"
  notification_channels = local.channel_ids

  user_labels = {
    area  = "availability"
    tier  = "critical"
    stack = var.stack_label
  }

  conditions {
    display_name = "No uptime metric for 5 minutes"

    condition_absent {
      filter   = "metric.type=\"compute.googleapis.com/instance/uptime\" AND ${local.gce_scope}"
      duration = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = <<-EOT
      **VM not reporting:** a monitored VM has sent no metrics for 5 minutes. It may be stopped, deleted or crashed.

      1. Compute Engine, VM instances: check the status.
      2. If it is stopped, start it. If it keeps crashing, read the serial console output.
    EOT
    mime_type = "text/markdown"
  }
}

# One dashboard that answers "is the system healthy?" at a glance: resources, network, application, availability.

locals {
  guide_title = "How to read this dashboard"
  guide_text  = <<-EOT
    **Resources** (rows 1-3): CPU, memory, disk and network of every VM. Healthy ranges: CPU below ${format("%.0f", var.cpu_warning_threshold * 100)}%, memory below ${var.memory_threshold_percent}%, disk below ${var.disk_threshold_percent}%.

    **Application** (rows 4-5): request rate, server errors and latency from the app log. p95 latency should stay under ${var.latency_threshold_ms} ms.

    **Availability** (row 6): share of health checks passing, from probes around the world.

    Alert policies fire on the same thresholds, so a line crossing its limit here has already notified the team.
  EOT

  widgets = [
    {
      title   = "CPU utilization (1.0 = 100%)"
      filter  = "metric.type=\"${local.cpu_metric}\" AND ${local.gce_scope}"
      aligner = "ALIGN_MEAN"
      period  = "60s"
    },
    {
      title   = "Memory used (%)"
      filter  = "metric.type=\"${local.memory_metric}\" AND metric.labels.state=\"used\" AND ${local.gce_scope}"
      aligner = "ALIGN_MEAN"
      period  = "60s"
    },
    {
      title   = "Disk space used (%)"
      filter  = "metric.type=\"${local.disk_metric}\" AND metric.labels.state=\"used\" AND ${local.gce_scope}"
      aligner = "ALIGN_MEAN"
      period  = "60s"
    },
    {
      title   = "Disk write throughput (bytes/s)"
      filter  = "metric.type=\"${local.disk_wr_metric}\" AND ${local.gce_scope}"
      aligner = "ALIGN_RATE"
      period  = "60s"
    },
    {
      title   = "Network sent (bytes/s)"
      filter  = "metric.type=\"${local.net_sent_metric}\" AND ${local.gce_scope}"
      aligner = "ALIGN_RATE"
      period  = "60s"
    },
    {
      title   = "Network received (bytes/s)"
      filter  = "metric.type=\"${local.net_recv_metric}\" AND ${local.gce_scope}"
      aligner = "ALIGN_RATE"
      period  = "60s"
    },
    {
      title   = "Requests per minute"
      filter  = "metric.type=\"${local.requests_metric}\" AND ${local.log_scope}"
      aligner = "ALIGN_SUM"
      period  = "60s"
    },
    {
      title   = "Server errors (HTTP 5xx) per minute"
      filter  = "metric.type=\"${local.errors_metric}\" AND ${local.log_scope}"
      aligner = "ALIGN_SUM"
      period  = "60s"
    },
    {
      title   = "Request latency p50 (ms)"
      filter  = "metric.type=\"${local.latency_metric}\" AND ${local.log_scope}"
      aligner = "ALIGN_PERCENTILE_50"
      period  = "60s"
    },
    {
      title   = "Request latency p95 (ms)"
      filter  = "metric.type=\"${local.latency_metric}\" AND ${local.log_scope}"
      aligner = "ALIGN_PERCENTILE_95"
      period  = "60s"
    },
    {
      title   = "Health checks passing (fraction)"
      filter  = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      aligner = "ALIGN_FRACTION_TRUE"
      period  = "300s"
    },
  ]

  chart_tiles = [
    for i, w in local.widgets : {
      xPos   = (i % 2) * 6
      yPos   = 3 + floor(i / 2) * 4
      width  = 6
      height = 4
      widget = {
        title = w.title
        xyChart = {
          dataSets = [{
            plotType = "LINE"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = w.filter
                aggregation = {
                  alignmentPeriod  = w.period
                  perSeriesAligner = w.aligner
                }
              }
            }
          }]
          yAxis = { scale = "LINEAR" }
        }
      }
    }
  ]

  guide_tile = {
    xPos   = 0
    yPos   = 0
    width  = 12
    height = 3
    widget = {
      title = local.guide_title
      text = {
        content = local.guide_text
        format  = "MARKDOWN"
      }
    }
  }
}

resource "google_monitoring_dashboard" "main" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "${var.name} | Performance overview"
    mosaicLayout = {
      columns = 12
      tiles   = concat([local.guide_tile], local.chart_tiles)
    }
  })
}

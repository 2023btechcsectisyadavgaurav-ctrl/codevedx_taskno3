locals {
  # Everything GCE-related is scoped to this stack's VMs through the `stack` label.
  gce_scope     = "resource.type=\"gce_instance\" AND metadata.user_labels.stack=\"${var.stack_label}\""
  metric_prefix = replace(var.name, "-", "_")

  # Log-based metrics have no VM labels, but Google requires every filter to name a resource type.
  log_scope = "resource.type=\"gce_instance\""

  app_log_filter = "resource.type=\"gce_instance\" AND logName=\"projects/${var.project_id}/logs/demo_app\""

  cpu_metric      = "compute.googleapis.com/instance/cpu/utilization"
  memory_metric   = "agent.googleapis.com/memory/percent_used"
  disk_metric     = "agent.googleapis.com/disk/percent_used"
  net_sent_metric = "compute.googleapis.com/instance/network/sent_bytes_count"
  net_recv_metric = "compute.googleapis.com/instance/network/received_bytes_count"
  disk_wr_metric  = "compute.googleapis.com/instance/disk/write_bytes_count"

  latency_metric  = "logging.googleapis.com/user/${local.metric_prefix}_app_latency_ms"
  errors_metric   = "logging.googleapis.com/user/${local.metric_prefix}_app_errors"
  requests_metric = "logging.googleapis.com/user/${local.metric_prefix}_app_requests"

  channel_ids = [for c in google_monitoring_notification_channel.email : c.id]
}

# ---------------------------------------------------------------------------
# Notifications: who is told when an alert fires
# ---------------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.alert_emails)

  project      = var.project_id
  display_name = "${var.name} | email ${each.value}"
  type         = "email"

  labels = {
    email_address = each.value
  }
}

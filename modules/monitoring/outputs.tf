output "dashboard_url" {
  description = "Console link to the dashboard."
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.main.id), 3)}?project=${var.project_id}"
}

output "alert_policy_names" {
  description = "Display names of all alert policies."
  value = concat(
    [for p in google_monitoring_alert_policy.threshold : p.display_name],
    [for p in google_monitoring_alert_policy.uptime : p.display_name],
    [google_monitoring_alert_policy.instance_down.display_name],
  )
}

output "alert_keys" {
  description = "Short identifiers of every alert policy."
  value = sort(concat(
    keys(local.threshold_alerts),
    [for zone in keys(var.hosts) : "uptime_${zone}"],
    ["instance_down"],
  ))
}

output "alert_severities" {
  description = "Distinct severity tiers used by the alert policies."
  value = sort(distinct(concat(
    [for a in local.threshold_alerts : a.severity],
    ["CRITICAL"],
  )))
}

output "monitored_areas" {
  description = "Areas covered by alert policies: cpu, memory, storage, network, application, availability, optimization."
  value = sort(distinct(concat(
    [for a in local.threshold_alerts : a.area],
    ["availability"],
  )))
}

output "all_filters" {
  description = "Every metric filter used by alert policies and dashboard charts (Google requires each to name a resource type)."
  value = concat(
    [for a in local.threshold_alerts : a.filter],
    [for w in local.widgets : w.filter],
  )
}

output "dashboard_widget_titles" {
  description = "Titles of every widget on the dashboard."
  value       = concat([local.guide_title], [for w in local.widgets : w.title])
}

output "log_metric_names" {
  description = "Application metrics derived from the app log."
  value = [
    google_logging_metric.app_requests.name,
    google_logging_metric.app_errors.name,
    google_logging_metric.app_latency.name,
  ]
}

output "uptime_check_count" {
  description = "Number of uptime checks."
  value       = length(google_monitoring_uptime_check_config.web)
}

output "notification_channel_count" {
  description = "Number of email notification channels."
  value       = length(google_monitoring_notification_channel.email)
}

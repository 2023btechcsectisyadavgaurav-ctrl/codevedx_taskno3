output "app_urls" {
  description = "URLs of the monitored web servers, one per zone."
  value       = { for zone, ip in module.workload.external_ips : zone => "http://${ip}" }
}

output "instance_names" {
  description = "Names of the monitored VMs, keyed by zone."
  value       = module.workload.instance_names
}

output "dashboard_url" {
  description = "Link to the Cloud Monitoring dashboard in the console."
  value       = module.monitoring.dashboard_url
}

output "alert_policy_names" {
  description = "Display names of every alert policy."
  value       = module.monitoring.alert_policy_names
}

output "notification_channels" {
  description = "Number of email notification channels created."
  value       = module.monitoring.notification_channel_count
}

output "demo_token" {
  description = "Token that unlocks the load-generating endpoints of the demo app (used by scripts/generate-load.ps1)."
  value       = random_password.demo_token.result
  sensitive   = true
}

# Exposed so the automated tests (tests/*.tftest.hcl) can assert on the design at plan time.
output "monitoring_summary" {
  description = "Coverage, alert tiers and security settings, asserted by the test suite."
  value = {
    monitored_areas   = module.monitoring.monitored_areas
    alert_keys        = module.monitoring.alert_keys
    alert_severities  = module.monitoring.alert_severities
    dashboard_widgets = module.monitoring.dashboard_widget_titles
    log_metrics       = module.monitoring.log_metric_names
    all_filters       = module.monitoring.all_filters
    uptime_checks     = module.monitoring.uptime_check_count
    instance_count    = module.workload.instance_count
    ssh_sources       = module.workload.ssh_source_ranges
    http_sources      = module.workload.http_source_ranges
    shielded_vm       = module.workload.shielded_vm_enabled
    vm_service_roles  = module.workload.service_account_roles
  }
}

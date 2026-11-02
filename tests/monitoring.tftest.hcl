# Offline tests: the providers are mocked, so no GCP account or credentials are needed.
# Run with:  terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "random" {}

variables {
  project_id = "test-project"
}

# --- Comprehensive: CPU, memory, storage, network and application are all monitored -------------
run "all_resource_areas_are_monitored" {
  command = plan

  assert {
    condition = alltrue([
      for area in ["cpu", "memory", "storage", "network", "application", "availability"] :
      contains(output.monitoring_summary.monitored_areas, area)
    ])
    error_message = "Alerts must cover cpu, memory, storage, network, application and availability."
  }

  assert {
    condition     = length(output.monitoring_summary.log_metrics) == 3
    error_message = "Three application metrics (requests, errors, latency) should be derived from the app log."
  }

  assert {
    condition     = output.monitoring_summary.instance_count == 2
    error_message = "Two web servers (one per default zone) should be monitored."
  }
}

# --- Accurate: filters are valid for the Cloud Monitoring API -----------------------------------
# Google rejects any alert or chart filter that does not name a resource type (this broke a real deployment once).
run "every_filter_names_a_resource_type" {
  command = plan

  assert {
    condition     = alltrue([for f in output.monitoring_summary.all_filters : strcontains(f, "resource.type=")])
    error_message = "Every alert and dashboard filter must contain a resource.type restriction."
  }

  assert {
    condition     = length(output.monitoring_summary.all_filters) >= 19
    error_message = "Expected the filters of all 8 threshold alerts and all 11 dashboard charts."
  }
}

# --- Accurate: every VM has its own uptime check and every metric has a policy -------------------
run "availability_is_checked_per_server" {
  command = plan

  assert {
    condition     = output.monitoring_summary.uptime_checks == 2
    error_message = "Each web server needs its own uptime check."
  }

  assert {
    condition     = contains(output.monitoring_summary.alert_keys, "uptime_us-central1-a") && contains(output.monitoring_summary.alert_keys, "uptime_us-central1-b")
    error_message = "Each uptime check needs its own alert policy."
  }

  assert {
    condition     = contains(output.monitoring_summary.alert_keys, "instance_down")
    error_message = "An alert must fire when a VM stops reporting."
  }
}

run "dashboard_has_resource_application_and_availability_charts" {
  command = plan

  assert {
    condition     = length(output.monitoring_summary.dashboard_widgets) >= 10
    error_message = "The dashboard should have at least ten widgets."
  }

  assert {
    condition = alltrue([
      for title in ["Memory used (%)", "Request latency p95 (ms)", "Server errors (HTTP 5xx) per minute", "Health checks passing (fraction)"] :
      contains(output.monitoring_summary.dashboard_widgets, title)
    ])
    error_message = "Dashboard is missing a memory, latency, error or availability chart."
  }
}

# --- Proactive: tiered alerts warn before things become critical --------------------------------
run "alerts_are_tiered_so_warnings_come_first" {
  command = plan

  assert {
    condition     = contains(output.monitoring_summary.alert_severities, "WARNING") && contains(output.monitoring_summary.alert_severities, "ERROR") && contains(output.monitoring_summary.alert_severities, "CRITICAL")
    error_message = "Alerts should use WARNING, ERROR and CRITICAL tiers."
  }

  assert {
    condition     = contains(output.monitoring_summary.alert_keys, "cpu_warning") && contains(output.monitoring_summary.alert_keys, "cpu_critical")
    error_message = "CPU needs both an early warning and a critical alert."
  }
}

run "notification_channels_follow_the_email_list" {
  command = plan

  variables {
    alert_emails = ["ops@example.com", "oncall@example.com"]
  }

  assert {
    condition     = output.notification_channels == 2
    error_message = "One notification channel is expected per alert email."
  }
}

# --- Efficient: over-provisioning is flagged ----------------------------------------------------
run "over_provisioned_vms_are_flagged" {
  command = plan

  assert {
    condition     = contains(output.monitoring_summary.monitored_areas, "optimization") && contains(output.monitoring_summary.alert_keys, "underutilized")
    error_message = "A cost-optimization alert for under-used VMs is required."
  }
}

# --- Secure workload ----------------------------------------------------------------------------
run "monitored_servers_are_hardened" {
  command = plan

  assert {
    condition     = output.monitoring_summary.shielded_vm
    error_message = "Monitored VMs must use Shielded VM."
  }

  assert {
    condition     = tolist(output.monitoring_summary.ssh_sources) == tolist(["35.235.240.0/20"])
    error_message = "SSH must be reachable only through Identity-Aware Proxy."
  }

  assert {
    condition     = tolist(output.monitoring_summary.vm_service_roles) == tolist(["roles/logging.logWriter", "roles/monitoring.metricWriter"])
    error_message = "The VM service account should only be able to write logs and metrics."
  }
}

run "ssh_rule_can_be_disabled" {
  command = plan

  variables {
    enable_iap_ssh = false
  }

  assert {
    condition     = length(output.monitoring_summary.ssh_sources) == 0
    error_message = "No SSH rule should exist when enable_iap_ssh is false."
  }
}

run "single_zone_is_supported" {
  command = plan

  variables {
    zones = ["us-central1-a"]
  }

  assert {
    condition     = output.monitoring_summary.instance_count == 1 && output.monitoring_summary.uptime_checks == 1
    error_message = "One zone should produce one VM and one uptime check."
  }
}

# --- Input validation ---------------------------------------------------------------------------
run "rejects_critical_below_warning" {
  command = plan

  variables {
    cpu_warning_threshold  = 0.8
    cpu_critical_threshold = 0.7
  }

  expect_failures = [var.cpu_critical_threshold]
}

run "rejects_invalid_email" {
  command = plan

  variables {
    alert_emails = ["not-an-email"]
  }

  expect_failures = [var.alert_emails]
}

run "rejects_too_many_zones" {
  command = plan

  variables {
    zones = ["us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f"]
  }

  expect_failures = [var.zones]
}

run "rejects_percent_out_of_range" {
  command = plan

  variables {
    memory_threshold_percent = 120
  }

  expect_failures = [var.memory_threshold_percent]
}

run "rejects_short_alert_duration" {
  command = plan

  variables {
    alert_duration_seconds = 10
  }

  expect_failures = [var.alert_duration_seconds]
}

run "rejects_bad_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

# Availability: Google probes /healthz on every web server from several locations around the world.
resource "google_monitoring_uptime_check_config" "web" {
  for_each = var.hosts

  project      = var.project_id
  display_name = "${var.name} | HTTP /healthz (${each.key})"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path           = "/healthz"
    port           = 80
    use_ssl        = false
    request_method = "GET"
  }

  content_matchers {
    content = "ok"
    matcher = "CONTAINS_STRING"
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = each.value
    }
  }
}

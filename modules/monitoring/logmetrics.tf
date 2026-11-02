# Application metrics: the demo app writes one JSON log line per request; these log-based metrics
# turn those lines into request-rate, error-count and latency-distribution metrics.

resource "google_logging_metric" "app_requests" {
  project     = var.project_id
  name        = "${local.metric_prefix}_app_requests"
  description = "HTTP requests served by the demo app"
  filter      = local.app_log_filter

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "app_errors" {
  project     = var.project_id
  name        = "${local.metric_prefix}_app_errors"
  description = "HTTP 5xx responses served by the demo app"
  filter      = "${local.app_log_filter} AND jsonPayload.status>=500"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "app_latency" {
  project         = var.project_id
  name            = "${local.metric_prefix}_app_latency_ms"
  description     = "Request latency of the demo app in milliseconds"
  filter          = local.app_log_filter
  value_extractor = "EXTRACT(jsonPayload.latency_ms)"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"
  }

  bucket_options {
    explicit_buckets {
      bounds = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
    }
  }
}

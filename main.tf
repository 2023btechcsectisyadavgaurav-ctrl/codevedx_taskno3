provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name = "${var.name_prefix}-${var.environment}"

  labels = merge(
    {
      project     = "cloud-monitoring-optimization"
      environment = var.environment
      managed-by  = "terraform"
    },
    var.extra_labels,
  )

  required_apis = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "recommender.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Shared secret that protects the load-generating endpoints of the demo app (/cpu, /mem, /slow, /error).
resource "random_password" "demo_token" {
  length  = 20
  special = false
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name        = local.name
  region      = var.region
  subnet_cidr = var.subnet_cidr

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# The workload being monitored: web servers running the Ops Agent
# ---------------------------------------------------------------------------
module "workload" {
  source = "./modules/workload"

  project_id           = var.project_id
  name                 = local.name
  region               = var.region
  zones                = var.zones
  machine_type         = var.machine_type
  subnetwork_self_link = module.network.subnetwork_self_link
  network_name         = module.network.network_name
  allowed_http_cidrs   = var.allowed_http_cidrs
  enable_iap_ssh       = var.enable_iap_ssh
  demo_token           = random_password.demo_token.result
  labels               = local.labels

  depends_on = [google_project_service.apis, module.network]
}

# ---------------------------------------------------------------------------
# Monitoring: uptime checks, log-based metrics, alert policies, dashboard
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  project_id                  = var.project_id
  name                        = local.name
  stack_label                 = local.name
  hosts                       = module.workload.external_ips
  alert_emails                = var.alert_emails
  alert_duration_seconds      = var.alert_duration_seconds
  cpu_warning_threshold       = var.cpu_warning_threshold
  cpu_critical_threshold      = var.cpu_critical_threshold
  memory_threshold_percent    = var.memory_threshold_percent
  disk_threshold_percent      = var.disk_threshold_percent
  network_threshold_mbps      = var.network_threshold_mbps
  latency_threshold_ms        = var.latency_threshold_ms
  error_threshold_count       = var.error_threshold_count
  underutilized_cpu_threshold = var.underutilized_cpu_threshold
  underutilized_hours         = var.underutilized_hours

  depends_on = [google_project_service.apis, module.workload]
}

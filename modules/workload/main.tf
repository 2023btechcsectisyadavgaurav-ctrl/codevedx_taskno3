data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

locals {
  # One VM per zone; the index gives each a stable, readable name (web-1, web-2, ...).
  zone_index = { for i, z in var.zones : z => i + 1 }

  vm_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}

# ---------------------------------------------------------------------------
# Identity: dedicated service account that can only write logs and metrics
# ---------------------------------------------------------------------------
resource "google_service_account" "vm" {
  project      = var.project_id
  account_id   = "${var.name}-vm"
  display_name = "Monitored web server (${var.name})"
}

resource "google_project_iam_member" "vm_roles" {
  for_each = toset(local.vm_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}

# ---------------------------------------------------------------------------
# Firewall: the demo site on port 80, SSH only through IAP
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_http" {
  name          = "${var.name}-allow-http"
  network       = var.network_name
  description   = "Public demo website (also reachable by Cloud Monitoring uptime checks)"
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = var.allowed_http_cidrs

  target_service_accounts = [google_service_account.vm.email]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  name          = "${var.name}-allow-iap-ssh"
  network       = var.network_name
  description   = "SSH only through Identity-Aware Proxy"
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]

  target_service_accounts = [google_service_account.vm.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ---------------------------------------------------------------------------
# Stable public IPs (uptime checks need a fixed address)
# ---------------------------------------------------------------------------
resource "google_compute_address" "web" {
  for_each = local.zone_index

  name         = "${var.name}-web-${each.value}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  labels       = var.labels
}

# ---------------------------------------------------------------------------
# The monitored VMs: Debian + Ops Agent + a small instrumented Python web app
# ---------------------------------------------------------------------------
resource "google_compute_instance" "web" {
  for_each = local.zone_index

  name         = "${var.name}-web-${each.value}"
  zone         = each.key
  machine_type = var.machine_type
  tags         = ["web"]

  # `stack` is what the alert policies and the dashboard filter on.
  labels = merge(var.labels, { stack = var.name, role = "web" })

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnetwork_self_link

    access_config {
      nat_ip = google_compute_address.web[each.key].address
    }
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    startup-script         = file("${path.module}/files/startup.sh")
    app-py                 = file("${path.module}/files/app.py")
    ops-agent-config       = file("${path.module}/files/ops-agent-config.yaml")
    demo-token             = var.demo_token
  }

  depends_on = [google_project_iam_member.vm_roles]
}

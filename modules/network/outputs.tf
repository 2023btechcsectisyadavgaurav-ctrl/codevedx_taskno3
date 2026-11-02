output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.vpc.name
}

output "subnetwork_self_link" {
  description = "Self link of the subnet."
  value       = google_compute_subnetwork.app.self_link
}

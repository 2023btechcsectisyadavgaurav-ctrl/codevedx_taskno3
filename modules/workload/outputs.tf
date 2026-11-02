output "external_ips" {
  description = "Static public IP of each VM, keyed by zone."
  value       = { for zone, addr in google_compute_address.web : zone => addr.address }
}

output "instance_names" {
  description = "Name of each VM, keyed by zone."
  value       = { for zone, vm in google_compute_instance.web : zone => vm.name }
}

output "instance_count" {
  description = "Number of monitored VMs."
  value       = length(google_compute_instance.web)
}

output "ssh_source_ranges" {
  description = "Source ranges allowed to SSH (only the IAP range, or empty)."
  value       = flatten([for r in google_compute_firewall.allow_iap_ssh : tolist(r.source_ranges)])
}

output "http_source_ranges" {
  description = "Source ranges allowed to reach port 80."
  value       = tolist(google_compute_firewall.allow_http.source_ranges)
}

output "shielded_vm_enabled" {
  description = "True when every VM has secure boot, vTPM and integrity monitoring on."
  value = alltrue(flatten([
    for vm in google_compute_instance.web : [
      vm.shielded_instance_config[0].enable_secure_boot,
      vm.shielded_instance_config[0].enable_vtpm,
      vm.shielded_instance_config[0].enable_integrity_monitoring,
    ]
  ]))
}

output "service_account_roles" {
  description = "Project roles granted to the VM service account."
  value       = sort(local.vm_roles)
}

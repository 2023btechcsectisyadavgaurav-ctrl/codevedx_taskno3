variable "project_id" {
  description = "Project that owns the resources."
  type        = string
}

variable "name" {
  description = "Name prefix for the workload resources."
  type        = string
}

variable "region" {
  description = "Region of the static IP addresses."
  type        = string
}

variable "zones" {
  description = "Zones to place one VM in each."
  type        = list(string)
}

variable "machine_type" {
  description = "Machine type of each VM."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Subnet the VMs attach to."
  type        = string
}

variable "network_name" {
  description = "VPC the firewall rules belong to."
  type        = string
}

variable "allowed_http_cidrs" {
  description = "Source ranges allowed to reach port 80."
  type        = list(string)
}

variable "enable_iap_ssh" {
  description = "Create the IAP-only SSH firewall rule."
  type        = bool
  default     = true
}

variable "demo_token" {
  description = "Token protecting the load-generating endpoints of the demo app."
  type        = string
  sensitive   = true
}

variable "labels" {
  description = "Labels applied to the VMs and addresses."
  type        = map(string)
  default     = {}
}

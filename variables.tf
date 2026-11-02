variable "project_id" {
  description = "GCP project ID that will hold every resource."
  type        = string
}

variable "region" {
  description = "Region for the network and the monitored VMs."
  type        = string
  default     = "us-central1"
}

variable "zones" {
  description = "Zones to place one monitored web server in each (1-3)."
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b"]

  validation {
    condition     = length(var.zones) >= 1 && length(var.zones) <= 3
    error_message = "Provide between one and three zones."
  }

  validation {
    condition     = length(distinct(var.zones)) == length(var.zones)
    error_message = "Zones must be unique."
  }
}

variable "environment" {
  description = "Environment name, used in resource names and labels."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "name_prefix" {
  description = "Prefix for all resource names (3-12 chars: lowercase letters, digits, hyphens)."
  type        = string
  default     = "cloudmon"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,11}$", var.name_prefix))
    error_message = "name_prefix must start with a letter, be 3-12 characters, and use only lowercase letters, digits and hyphens."
  }
}

# ---------------------------------------------------------------------------
# Workload
# ---------------------------------------------------------------------------
variable "machine_type" {
  description = "Machine type of the monitored web servers."
  type        = string
  default     = "e2-small"
}

variable "subnet_cidr" {
  description = "CIDR range of the subnet."
  type        = string
  default     = "10.20.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block."
  }
}

variable "allowed_http_cidrs" {
  description = "Source ranges allowed to reach the demo website on port 80 (it is a public demo site by design). Narrow this to your own IP for a private demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_iap_ssh" {
  description = "Allow SSH only through Identity-Aware Proxy (no public SSH)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------
variable "alert_emails" {
  description = "Email addresses that receive alert notifications. Leave empty to create the alerts without notifications."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every alert email must be a valid email address."
  }
}

variable "alert_duration_seconds" {
  description = "How long a condition must hold before an alert fires. 120 is good for demos; use 300 or more in production to avoid noise."
  type        = number
  default     = 120

  validation {
    condition     = var.alert_duration_seconds >= 60 && var.alert_duration_seconds <= 3600
    error_message = "alert_duration_seconds must be between 60 and 3600."
  }
}

variable "cpu_warning_threshold" {
  description = "CPU utilization (0-1) that raises a WARNING, before users are affected."
  type        = number
  default     = 0.7

  validation {
    condition     = var.cpu_warning_threshold > 0 && var.cpu_warning_threshold < 1
    error_message = "cpu_warning_threshold must be between 0 and 1 (exclusive)."
  }
}

variable "cpu_critical_threshold" {
  description = "CPU utilization (0-1) that raises a CRITICAL alert."
  type        = number
  default     = 0.9

  validation {
    condition     = var.cpu_critical_threshold > var.cpu_warning_threshold && var.cpu_critical_threshold <= 1
    error_message = "cpu_critical_threshold must be greater than cpu_warning_threshold and at most 1."
  }
}

variable "memory_threshold_percent" {
  description = "Memory used (percent) that raises an alert."
  type        = number
  default     = 85

  validation {
    condition     = var.memory_threshold_percent > 0 && var.memory_threshold_percent < 100
    error_message = "memory_threshold_percent must be between 0 and 100 (exclusive)."
  }
}

variable "disk_threshold_percent" {
  description = "Disk space used (percent) that raises an alert."
  type        = number
  default     = 80

  validation {
    condition     = var.disk_threshold_percent > 0 && var.disk_threshold_percent < 100
    error_message = "disk_threshold_percent must be between 0 and 100 (exclusive)."
  }
}

variable "network_threshold_mbps" {
  description = "Outbound network throughput (megabytes per second per VM) that raises an alert."
  type        = number
  default     = 20

  validation {
    condition     = var.network_threshold_mbps > 0
    error_message = "network_threshold_mbps must be greater than 0."
  }
}

variable "latency_threshold_ms" {
  description = "95th percentile request latency (milliseconds) that raises an alert."
  type        = number
  default     = 500

  validation {
    condition     = var.latency_threshold_ms > 0
    error_message = "latency_threshold_ms must be greater than 0."
  }
}

variable "error_threshold_count" {
  description = "Number of server errors (HTTP 5xx) in 5 minutes that raises an alert."
  type        = number
  default     = 5

  validation {
    condition     = var.error_threshold_count >= 1
    error_message = "error_threshold_count must be at least 1."
  }
}

variable "underutilized_cpu_threshold" {
  description = "CPU utilization (0-1) below which a VM is flagged as over-provisioned (cost optimization)."
  type        = number
  default     = 0.05

  validation {
    condition     = var.underutilized_cpu_threshold > 0 && var.underutilized_cpu_threshold < 0.5
    error_message = "underutilized_cpu_threshold must be between 0 and 0.5 (exclusive)."
  }
}

variable "underutilized_hours" {
  description = "Hours of sustained low CPU before the over-provisioned alert fires (1-24)."
  type        = number
  default     = 6

  validation {
    condition     = var.underutilized_hours >= 1 && var.underutilized_hours <= 24
    error_message = "underutilized_hours must be between 1 and 24."
  }
}

variable "extra_labels" {
  description = "Additional labels applied to every resource that supports labels."
  type        = map(string)
  default     = {}
}

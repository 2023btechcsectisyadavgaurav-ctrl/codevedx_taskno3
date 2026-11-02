variable "project_id" {
  description = "Project that owns the monitoring resources."
  type        = string
}

variable "name" {
  description = "Name prefix for monitoring resources."
  type        = string
}

variable "stack_label" {
  description = "Value of the `stack` label on the monitored VMs; alerts and charts are scoped to it."
  type        = string
}

variable "hosts" {
  description = "Public IP of each web server, keyed by zone. One uptime check is created per entry."
  type        = map(string)
}

variable "alert_emails" {
  description = "Email addresses that receive alert notifications."
  type        = list(string)
  default     = []
}

variable "alert_duration_seconds" {
  description = "Seconds a condition must hold before an alert fires."
  type        = number
}

variable "cpu_warning_threshold" {
  description = "CPU utilization (0-1) for the WARNING alert."
  type        = number
}

variable "cpu_critical_threshold" {
  description = "CPU utilization (0-1) for the CRITICAL alert."
  type        = number
}

variable "memory_threshold_percent" {
  description = "Memory used (percent) alert threshold."
  type        = number
}

variable "disk_threshold_percent" {
  description = "Disk used (percent) alert threshold."
  type        = number
}

variable "network_threshold_mbps" {
  description = "Outbound megabytes per second alert threshold."
  type        = number
}

variable "latency_threshold_ms" {
  description = "p95 latency alert threshold in milliseconds."
  type        = number
}

variable "error_threshold_count" {
  description = "HTTP 5xx count in 5 minutes alert threshold."
  type        = number
}

variable "underutilized_cpu_threshold" {
  description = "CPU utilization (0-1) below which a VM is flagged as over-provisioned."
  type        = number
}

variable "underutilized_hours" {
  description = "Hours of sustained low CPU before the over-provisioned alert fires."
  type        = number
}

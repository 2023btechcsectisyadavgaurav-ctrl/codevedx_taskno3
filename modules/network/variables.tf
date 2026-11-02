variable "name" {
  description = "Name prefix for network resources."
  type        = string
}

variable "region" {
  description = "Region of the subnet."
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range of the subnet."
  type        = string
}

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the Memorystore instance."
  type        = string
}

variable "name" {
  description = "Redis instance name."
  type        = string
}

variable "network_self_link" {
  description = "VPC network self_link to authorize."
  type        = string
}

variable "memory_size_gb" {
  description = "Redis memory size in GB."
  type        = number
  default     = 1
}

variable "redis_version" {
  description = "Redis version (e.g., REDIS_7_0)."
  type        = string
  default     = "REDIS_7_0"
}

variable "tier" {
  description = "Redis tier (BASIC or STANDARD_HA)."
  type        = string
  default     = "BASIC"
}

variable "enable_private_service_access" {
  description = "Whether to provision the private service access connection for Memorystore."
  type        = bool
  default     = true
}

variable "private_service_access_range_name" {
  description = "Name for the reserved peering range."
  type        = string
  default     = "redis-private-service-range"
}

variable "private_service_access_prefix_length" {
  description = "Prefix length for reserved peering range (e.g., 16)."
  type        = number
  default     = 16
}


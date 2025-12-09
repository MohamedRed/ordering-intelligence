variable "project_id" {
  description = "GCP project ID for the environment."
  type        = string
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "us-central1"
}

variable "environment_name" {
  description = "Identifier for the deployment environment (e.g., staging)."
  type        = string
  default     = "staging"
}

variable "billing_account" {
  description = "Billing account for project creation (optional)."
  type        = string
  default     = ""
}

variable "image_registry_project" {
  description = "GCP project that hosts shared container images (default uses this environment's project)."
  type        = string
  default     = ""
}

variable "cloud_run_overrides" {
  description = "Optional per-service overrides for Cloud Run runtime settings and environment variables."
  type = map(object({
    min_scale             = optional(number)
    max_scale             = optional(number)
    container_concurrency = optional(number)
    timeout_seconds       = optional(number)
    cpu                   = optional(string)
    memory                = optional(string)
    startup_cpu_boost     = optional(bool)
    env_overrides         = optional(map(string))
    secret_env_overrides  = optional(map(string))
  }))
  default = {}
}

variable "waf_blocked_ip_ranges" {
  description = "Optional static IP ranges to block at the Cloud Armor policy."
  type        = list(string)
  default     = []
}

variable "order_service_lb_hostname" {
  description = "Logical hostname used for the staging order service load balancer certificate."
  type        = string
  default     = "order-service-staging.local"
}

variable "order_service_lb_certificate_mode" {
  description = "Certificate mode for the staging load balancer (SELF_SIGNED or MANAGED)."
  type        = string
  default     = "SELF_SIGNED"
}

variable "order_service_lb_managed_domains" {
  description = "Optional explicit domains for managed certificates (defaults to nip.io domain)."
  type        = list(string)
  default     = []
}

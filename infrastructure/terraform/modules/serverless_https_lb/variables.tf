variable "project_id" {
  description = "GCP project hosting the Cloud Run service."
  type        = string
}

variable "region" {
  description = "Region for the Cloud Run service."
  type        = string
}

variable "cloud_run_service" {
  description = "Cloud Run service name to expose."
  type        = string
}

variable "environment_name" {
  description = "Environment identifier (e.g., staging, prod)."
  type        = string
}

variable "hostname" {
  description = "Hostname used for the self-signed certificate common name."
  type        = string
}

variable "security_policy_id" {
  description = "Cloud Armor security policy ID to attach to the backend service."
  type        = string
  default     = null
}

variable "certificate_mode" {
  description = "Certificate mode: SELF_SIGNED or MANAGED."
  type        = string
  default     = "SELF_SIGNED"
}

variable "managed_domains" {
  description = "Optional list of domains for the managed certificate (defaults to nip.io hostname)."
  type        = list(string)
  default     = []
}

variable "backend_timeout_seconds" {
  description = "Timeout for the backend service."
  type        = number
  default     = 30
}

variable "certificate_validity_hours" {
  description = "Validity period for the self-signed certificate."
  type        = number
  default     = 4380 # 6 months
}

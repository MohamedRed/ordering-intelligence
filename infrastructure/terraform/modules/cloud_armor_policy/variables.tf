variable "project_id" {
  description = "GCP project ID for the policy."
  type        = string
}

variable "policy_name" {
  description = "Name of the Cloud Armor security policy."
  type        = string
}

variable "description" {
  description = "Description for the policy."
  type        = string
  default     = ""
}

variable "blocked_ip_ranges" {
  description = "Static list of IP ranges to block."
  type        = list(string)
  default     = []
}

variable "enable_rate_limit" {
  description = "Whether to enable the default per-IP rate limit rule."
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Requests per interval before throttling."
  type        = number
  default     = 600
}

variable "rate_limit_interval_seconds" {
  description = "Length of the rate limit window in seconds."
  type        = number
  default     = 60
}

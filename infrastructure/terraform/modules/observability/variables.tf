variable "project_id" {
  description = "GCP project to provision monitoring resources in."
  type        = string
}

variable "environment" {
  description = "Environment label (dev/staging/prod)."
  type        = string
}

variable "telephony_service_name" {
  description = "Cloud Run service name for legacy telephony adapter dashboards (deprecated)."
  type        = string
  default     = "order-service"
}

variable "conversation_service_name" {
  description = "Cloud Run service name for legacy conversation orchestrator dashboards (deprecated)."
  type        = string
  default     = "order-service"
}

variable "email_notification_addresses" {
  description = "Email addresses to receive alert notifications."
  type        = list(string)
  default     = []
}

variable "notification_channel_ids" {
  description = "Existing Monitoring notification channel IDs to attach to alert policies."
  type        = list(string)
  default     = []
}

variable "enable_dashboards" {
  description = "Whether to provision opinionated dashboards."
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Whether to provision baseline alert policies."
  type        = bool
  default     = true
}

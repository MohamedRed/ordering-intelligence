variable "notification_service_push_endpoint" {
  description = "Push endpoint for notification-service order events"
  type        = string
}

variable "notification_service_sa_email" {
  description = "Service account email used for Pub/Sub push OIDC token"
  type        = string
}

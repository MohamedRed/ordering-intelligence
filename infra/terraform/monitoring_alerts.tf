variable "order_service_host" {
  description = "Host (and optional port) for order-service health check, e.g. order-service.example.com"
  type        = string
  default     = "order-service.example.com"
}

variable "notification_service_host" {
  description = "Host (and optional port) for notification-service health check"
  type        = string
  default     = "notification-service.example.com"
}

variable "alert_channel_ids" {
  description = "Monitoring channel IDs (email/SMS/webhook) to notify"
  type        = list(string)
  default     = []
}

resource "google_monitoring_uptime_check_config" "order_service" {
  display_name = "order-service-uptime"

  http_check {
    path = "/healthz/"
  }

  monitored_resource {
    type   = "uptime_url"
    labels = { host = var.order_service_host }
  }
}

resource "google_monitoring_uptime_check_config" "notification_service" {
  display_name = "notification-service-uptime"

  http_check {
    path = "/healthz"
  }

  monitored_resource {
    type   = "uptime_url"
    labels = { host = var.notification_service_host }
  }
}

resource "google_monitoring_alert_policy" "uptime_critical" {
  display_name = "Services down (order/notification)"
  combiner     = "OR"

  conditions {
    display_name = "Order service down"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.label.\"host\"=\"${var.order_service_host}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
    }
  }

  conditions {
    display_name = "Notification service down"
    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.label.\"host\"=\"${var.notification_service_host}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
    }
  }

  notification_channels = var.alert_channel_ids
  documentation {
    content = "Services failed uptime checks for 5 minutes. Investigate rollout or infra."
  }
}

resource "google_monitoring_alert_policy" "push_failures" {
  display_name = "Notification push failures"
  combiner     = "OR"

  conditions {
    display_name = "Push failures > 5 in 5m"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/notifications_push_failed_total\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  notification_channels = var.alert_channel_ids
  documentation {
    content = "Notification service is seeing push delivery failures. Check FCM/APNs credentials and topic subscriptions."
  }
}

variable "menu_ingest_subscription" {
  description = "Name of the menu ingestion push subscription (for backlog alert)"
  type        = string
  default     = "menu-ingest-push"
}

variable "menu_ingest_backlog_threshold" {
  description = "Backlog message threshold for menu ingestion"
  type        = number
  default     = 10
}

resource "google_monitoring_alert_policy" "menu_ingest_backlog" {
  display_name = "Menu ingestion backlog"
  combiner     = "OR"

  conditions {
    display_name = "menu-ingest-push backlog > threshold"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.\"subscription_id\"=\"${var.menu_ingest_subscription}\""
      duration        = "600s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.menu_ingest_backlog_threshold
    }
  }

  notification_channels = var.alert_channel_ids
  documentation {
    content = "Menu ingestion queue is backing up. Check Cloud Run logs and Gemini quotas."
  }
}

variable "menu_ingest_dlq_subscription" {
  description = "Name of the menu ingestion DLQ subscription (if using BigQuery sink) or topic for alerting"
  type        = string
  default     = "menu-ingest-dlq"
}

resource "google_monitoring_alert_policy" "menu_ingest_dlq" {
  display_name = "Menu ingestion DLQ non-zero"
  combiner     = "OR"

  conditions {
    display_name = "menu-ingest-dlq messages present"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.\"subscription_id\"=\"${var.menu_ingest_dlq_subscription}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
    }
  }

  notification_channels = var.alert_channel_ids
  documentation {
    content = "Messages landed in the menu ingestion DLQ. Investigate job failures or Gemini quota issues."
  }
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

locals {
  dashboards = var.enable_dashboards ? {
    telephony = templatefile(
      "${path.module}/templates/telephony_dashboard.json",
      {
        environment  = var.environment,
        service_name = var.telephony_service_name
      }
    )
    orchestrator = templatefile(
      "${path.module}/templates/orchestrator_dashboard.json",
      {
        environment  = var.environment,
        service_name = var.conversation_service_name
      }
    )
    analytics = templatefile(
      "${path.module}/templates/analytics_dashboard.json",
      {
        environment               = var.environment,
        telephony_service_name    = var.telephony_service_name,
        conversation_service_name = var.conversation_service_name
      }
    )
  } : {}
}

resource "google_monitoring_notification_channel" "email" {
  for_each = toset(var.email_notification_addresses)

  type         = "email"
  display_name = each.key
  labels = {
    email_address = each.key
  }
}

resource "google_monitoring_dashboard" "dashboards" {
  for_each = local.dashboards

  dashboard_json = each.value
}

locals {
  alert_notification_channels = var.enable_alerts ? concat(
    var.notification_channel_ids,
    [for channel in google_monitoring_notification_channel.email : channel.name]
  ) : []
}

resource "google_monitoring_alert_policy" "telephony_5xx" {
  count                 = var.enable_alerts ? 1 : 0
  display_name          = "Telephony Adapter 5xx rate (${var.environment})"
  combiner              = "OR"
  notification_channels = local.alert_notification_channels

  documentation {
    content = "High 5xx rate detected for telephony adapter in ${var.environment}. Investigate Cloud Run revisions, Twilio webhooks, and LiveKit connectivity."
  }

  conditions {
    display_name = "5xx requests per minute"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.\"service_name\"=\"${var.telephony_service_name}\" metric.label.\"response_code_class\"=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"

      aggregations {
        per_series_aligner = "ALIGN_DELTA"
        alignment_period   = "60s"
      }

      trigger {
        count = 1
      }
    }
  }
}

resource "google_monitoring_alert_policy" "orchestrator_latency" {
  count                 = var.enable_alerts ? 1 : 0
  display_name          = "Conversation Orchestrator latency (${var.environment})"
  combiner              = "OR"
  notification_channels = local.alert_notification_channels

  documentation {
    content = "Order service latency exceeded threshold in ${var.environment}. Review Firestore latency, Pub/Sub backlog, and downstream dependencies."
  }

  conditions {
    display_name = "P95 latency"

    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.label.\"service_name\"=\"${var.conversation_service_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 800
      duration        = "300s"

      aggregations {
        per_series_aligner = "ALIGN_PERCENTILE_95"
        alignment_period   = "60s"
      }

      trigger {
        count = 1
      }
    }
  }
}

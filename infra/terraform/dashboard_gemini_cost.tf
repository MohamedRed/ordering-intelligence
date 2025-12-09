variable "project_id" {
  description = "Project ID for the monitoring dashboard"
  type        = string
  default     = ""
}

resource "google_monitoring_dashboard" "gemini_menu_ingestion" {
  dashboard_json = <<EOF
{
  "displayName": "Menu Ingestion / Gemini Cost Guard",
  "gridLayout": {
    "columns": 2,
    "widgets": [
      {
        "title": "Gemini Requests (menu-ingestion)",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.\"response_code\"=~\"2..\" AND resource.label.\"service_name\"=\"menu-ingestion\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              },
              "plotType": "LINE"
            }
          ],
          "chartOptions": { "mode": "COLOR" }
        }
      },
      {
        "title": "Pub/Sub backlog: menu-ingest-push",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\" AND resource.label.\"subscription_id\"=\"menu-ingest-push\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              },
              "plotType": "LINE"
            }
          ]
        }
      },
      {
        "title": "Menu updates delivered (order-service)",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND resource.label.\"service_name\"=\"order-service\" AND metric.label.\"response_code\"=~\"2..\" AND metadata.user_label.\"path\"=\"/events/menu-updates\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              },
              "plotType": "LINE"
            }
          ]
        }
      },
      {
        "title": "Menu ingestion status (Firestore)",
        "scorecard": {
          "timeSeriesQuery": {
            "timeSeriesFilter": {
              "filter": "metric.type=\"firestore.googleapis.com/document/count\" AND resource.label.\"collection_id\"=\"menus_ingest\"",
              "aggregation": {
                "alignmentPeriod": "3600s",
                "perSeriesAligner": "ALIGN_MEAN"
              }
            }
          }
        }
      }
    ]
  }
}
EOF
}

locals {
  order_service_host = "${local.service_names.order_service}-${local.project_number}.${var.region}.run.app"
}

resource "google_monitoring_uptime_check_config" "order_service" {
  display_name = "order-service-uptime (dev)"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path    = "/healthz/"
    port    = 443
    use_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = local.order_service_host
    }
  }
}

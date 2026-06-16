locals {
  ingress_map = {
    "all"                               = "INGRESS_TRAFFIC_ALL"
    "internal"                          = "INGRESS_TRAFFIC_INTERNAL_ONLY"
    "internal-and-cloud-load-balancing" = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  }

  effective_ingress = lookup(local.ingress_map, var.ingress, "INGRESS_TRAFFIC_ALL")

  plain_env = [
    for name, value in var.env_vars : {
      name  = name
      value = value
    }
  ]

  secret_env = [
    for name, secret in var.secret_env_vars : {
      name   = name
      secret = secret
    }
  ]
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.service_name
  project  = var.project_id
  location = var.location

  ingress = local.effective_ingress
  labels  = var.labels

  template {
    labels = var.labels
    annotations = merge(
      {
        "autoscaling.knative.dev/maxScale" = tostring(var.max_scale)
      },
      var.min_scale > 0 ? {
        "autoscaling.knative.dev/minScale" = tostring(var.min_scale)
      } : {},
      var.startup_cpu_boost ? {
        "run.googleapis.com/startup-cpu-boost" = "true"
      } : {}
    )

    execution_environment            = var.execution_environment
    service_account                  = var.service_account
    timeout                          = "${var.timeout_seconds}s"
    max_instance_request_concurrency = var.container_concurrency

    scaling {
      min_instance_count = var.min_scale
      max_instance_count = var.max_scale
    }

    containers {
      image = var.image

      dynamic "env" {
        for_each = local.plain_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = local.secret_env
        content {
          name = env.value.name
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = var.secret_version
            }
          }
        }
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }
    }

    dynamic "vpc_access" {
      for_each = var.direct_vpc_network != null && var.direct_vpc_network != "" && var.direct_vpc_subnetwork != null && var.direct_vpc_subnetwork != "" ? [1] : []
      content {
        egress = var.direct_vpc_egress
        network_interfaces {
          network    = var.direct_vpc_network
          subnetwork = var.direct_vpc_subnetwork
        }
      }
    }
  }
}



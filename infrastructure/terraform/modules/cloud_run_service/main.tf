locals {
  service_annotations = {
    "run.googleapis.com/ingress" = var.ingress
  }

  template_annotations = merge(
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

resource "google_cloud_run_service" "this" {
  name     = var.service_name
  project  = var.project_id
  location = var.location

  autogenerate_revision_name = true

  metadata {
    annotations = local.service_annotations
    labels      = var.labels
  }

  template {
    metadata {
      annotations = local.template_annotations
      labels      = var.labels
    }

    spec {
      container_concurrency = var.container_concurrency
      timeout_seconds       = var.timeout_seconds
      service_account_name  = var.service_account

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
            value_from {
              secret_key_ref {
                name = env.value.secret
                key  = var.secret_version
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
    }
  }

  traffic {
    latest_revision = true
    percent         = 100
  }
}

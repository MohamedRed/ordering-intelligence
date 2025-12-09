terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

module "core" {
  source          = "../../modules/core"
  project_id      = var.project_id
  region          = var.region
  billing_account = var.billing_account
  run_service_accounts = [
    module.order_service_sa.email,
    module.menu_ingestion_sa.email
  ]
}

locals {
  service_names = {
    order_service  = "order-service"
    menu_ingestion = "menu-ingestion"
    notification_service = "notification-service"
  }

  project_number = tostring(data.google_project.current.number)

  image_registry_project = var.image_registry_project != "" ? var.image_registry_project : var.project_id

  service_urls = {
    for key, name in local.service_names :
    key => "https://${name}-${local.project_number}.${var.region}.run.app"
  }

  order_service_lb_url = module.order_service_lb.hostname != "" ? "https://${module.order_service_lb.hostname}" : local.service_urls.order_service

  cloud_run_defaults = {
    order_service = {
      min_scale             = 0
      max_scale             = 20
      container_concurrency = 80
      timeout_seconds       = 300
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides         = {}
      secret_env_overrides  = {}
    }
    menu_ingestion = {
      min_scale             = 0
      max_scale             = 20
      container_concurrency = 60
      timeout_seconds       = 300
      cpu                   = "1000m"
      memory                = "512Mi"
      startup_cpu_boost     = true
      env_overrides         = {
        MENU_BUCKET          = "${var.project_id}-menus-${var.environment_name}"
        MENU_INGEST_TOPIC    = "menu-ingest"
        MENU_UPDATES_TOPIC   = "menu-updates"
        VERTEX_PROJECT       = var.project_id
        VERTEX_LOCATION      = var.region
        VERTEX_MODEL         = "gemini-2.5-flash"
        GOOGLE_CLOUD_PROJECT = var.project_id
      }
      secret_env_overrides  = {}
    }
  }

  cloud_run_config = {
    for key, defaults in local.cloud_run_defaults :
    key => merge(
      defaults,
      try(var.cloud_run_overrides[key], {})
    )
  }
}

module "order_service_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "order-service-${var.environment_name}"
  display_name = "Order Service (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/datastore.user"
  ]
}

module "menu_ingestion_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "menu-ingestion-${var.environment_name}"
  display_name = "Menu Ingestion (${var.environment_name})"
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
    "roles/storage.objectAdmin",
    "roles/pubsub.publisher",
    "roles/aiplatform.user",
    "roles/editor"
  ]
}

resource "google_pubsub_topic_iam_member" "order_pubsub_publisher" {
  project = var.project_id
  topic   = module.core.pubsub_topics["orders-events"]
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.order_service_sa.email}"
}

resource "google_pubsub_topic" "menu_ingest" {
  name    = "menu-ingest"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_pubsub_topic" "menu_ingest_dlq" {
  name    = "menu-ingest-dlq"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_pubsub_topic" "menu_updates" {
  name    = "menu-updates"
  project = var.project_id
  labels = {
    environment = var.environment_name
    service     = "menu-ingestion"
  }
}

resource "google_pubsub_topic_iam_member" "menu_updates_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.menu_updates.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.menu_ingestion_sa.email}"
}

resource "google_project_iam_member" "cloudservices_serviceusage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${tostring(data.google_project.current.number)}@cloudservices.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudservices_projectiam" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${tostring(data.google_project.current.number)}@cloudservices.gserviceaccount.com"
}

resource "google_storage_bucket" "menu_ingestion" {
  name     = "${var.project_id}-menus-${var.environment_name}"
  location = var.region
  project  = var.project_id

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "menu_ingestion_sa_access" {
  bucket = google_storage_bucket.menu_ingestion.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.menu_ingestion_sa.email}"
}

resource "google_project_iam_audit_config" "all_services" {
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

module "order_service" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.order_service
  image                 = "us-central1-docker.pkg.dev/${local.image_registry_project}/services/order-service:latest"
  min_scale             = local.cloud_run_config.order_service.min_scale
  max_scale             = local.cloud_run_config.order_service.max_scale
  container_concurrency = local.cloud_run_config.order_service.container_concurrency
  timeout_seconds       = local.cloud_run_config.order_service.timeout_seconds
  cpu                   = local.cloud_run_config.order_service.cpu
  memory                = local.cloud_run_config.order_service.memory
  startup_cpu_boost     = local.cloud_run_config.order_service.startup_cpu_boost
  service_account       = module.order_service_sa.email

  env_vars = merge({
    ENVIRONMENT          = var.environment_name
    FIRESTORE_PROJECT_ID = var.project_id
    PUBSUB_TOPIC_ORDERS  = "orders-events"
  }, lookup(local.cloud_run_config.order_service, "env_overrides", {}))

  depends_on = [
    module.core,
    module.order_service_sa,
    google_pubsub_topic_iam_member.order_pubsub_publisher
  ]
}

module "menu_ingestion" {
  source                = "../../modules/cloud_run_service"
  project_id            = var.project_id
  location              = var.region
  service_name          = local.service_names.menu_ingestion
  image                 = "us-central1-docker.pkg.dev/${local.image_registry_project}/services/menu-ingestion:latest"
  min_scale             = local.cloud_run_config.menu_ingestion.min_scale
  max_scale             = local.cloud_run_config.menu_ingestion.max_scale
  container_concurrency = local.cloud_run_config.menu_ingestion.container_concurrency
  timeout_seconds       = local.cloud_run_config.menu_ingestion.timeout_seconds
  cpu                   = local.cloud_run_config.menu_ingestion.cpu
  memory                = local.cloud_run_config.menu_ingestion.memory
  startup_cpu_boost     = local.cloud_run_config.menu_ingestion.startup_cpu_boost
  service_account       = module.menu_ingestion_sa.email
  env_vars              = merge({
    ENVIRONMENT = var.environment_name
  }, lookup(local.cloud_run_config.menu_ingestion, "env_overrides", {}))

  depends_on = [
    module.core,
    module.menu_ingestion_sa,
    google_storage_bucket.menu_ingestion,
    google_pubsub_topic.menu_ingest
  ]
}

resource "google_pubsub_subscription" "menu_ingest_push" {
  name   = "menu-ingest-push"
  topic  = google_pubsub_topic.menu_ingest.name
  project = var.project_id

  push_config {
    push_endpoint = "${local.service_urls.menu_ingestion}/tasks/process"
    oidc_token {
      service_account_email = module.menu_ingestion_sa.email
    }
  }

  ack_deadline_seconds = 30

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.menu_ingest_dlq.name
    max_delivery_attempts = 5
  }
}

resource "google_cloud_run_service_iam_member" "order_service_lb_invoker" {
  project  = var.project_id
  location = var.region
  service  = local.service_names.order_service
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${local.project_number}@serverless-robot-prod.iam.gserviceaccount.com"

  depends_on = [module.order_service]
}

module "order_service_waf" {
  source      = "../../modules/cloud_armor_policy"
  project_id  = var.project_id
  policy_name = "${var.environment_name}-order-service-waf"
  description = "Baseline Cloud Armor policy for prod order service."

  blocked_ip_ranges           = var.waf_blocked_ip_ranges
  enable_rate_limit           = true
  rate_limit_threshold        = 600
  rate_limit_interval_seconds = 60
}

module "order_service_lb" {
  source             = "../../modules/serverless_https_lb"
  project_id         = var.project_id
  region             = var.region
  cloud_run_service  = local.service_names.order_service
  environment_name   = var.environment_name
  hostname           = var.order_service_lb_hostname
  security_policy_id = module.order_service_waf.policy_id
  certificate_mode   = var.order_service_lb_certificate_mode
  managed_domains    = var.order_service_lb_managed_domains
}

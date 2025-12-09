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

resource "google_project_service" "enabled" {
  for_each = toset(var.enable_services)

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

resource "google_compute_network" "core" {
  name                    = var.network_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "core" {
  name          = "${var.network_name}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.core.id
  ip_cidr_range = var.subnet_cidr_range
  stack_type    = "IPV4_ONLY"
}

resource "google_artifact_registry_repository" "services" {
  location      = var.region
  repository_id = var.artifact_registry_repository
  project       = var.project_id
  format        = var.artifact_registry_format
  description   = "Container images for Ordering Intelligence services."
}

resource "google_firestore_database" "default" {
  project          = var.project_id
  name             = "(default)"
  location_id      = var.firestore_location
  type             = "FIRESTORE_NATIVE"
  concurrency_mode = "OPTIMISTIC"
}

resource "google_pubsub_topic" "topics" {
  for_each = toset(var.pubsub_topics)

  name    = each.value
  project = var.project_id
  labels = {
    environment = "shared"
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each = toset(var.secret_names)

  secret_id = each.value
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_binding" "run_accessor" {
  for_each = length(var.run_service_accounts) > 0 ? toset(var.secret_names) : toset([])

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  members   = [for sa in var.run_service_accounts : "serviceAccount:${sa}"]

  depends_on = [google_secret_manager_secret.secrets]
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id                  = var.analytics_dataset_id
  project                     = var.project_id
  location                    = var.bigquery_location
  delete_contents_on_destroy  = false
  default_table_expiration_ms = null
  labels = {
    environment = var.region
  }
  depends_on = [google_project_service.enabled]
}

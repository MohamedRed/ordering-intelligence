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
  project = null
  region  = var.default_region
}

locals {
  parent_org_id  = var.folder_id == "" ? var.org_id : null
  parent_folder  = var.folder_id != "" ? var.folder_id : null
  labels         = var.project_labels
}

resource "google_project" "this" {
  project_id      = var.project_id
  name            = var.project_name
  org_id          = local.parent_org_id
  folder_id       = local.parent_folder
  billing_account = null # linked via google_billing_project
  labels          = local.labels
}

# Link billing once the project exists.
resource "google_billing_project" "link" {
  project         = google_project.this.project_id
  billing_account = var.billing_account
}

# Enable only the APIs needed for the main stack to proceed.
resource "google_project_service" "bootstrap_services" {
  for_each = toset(var.enable_apis)

  project             = google_project.this.project_id
  service             = each.value
  disable_on_destroy  = false
  depends_on          = [google_billing_project.link]
}

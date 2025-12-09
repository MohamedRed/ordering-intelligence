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
}

resource "google_project_iam_custom_role" "this" {
  project     = var.project_id
  role_id     = var.role_id
  title       = var.title
  description = var.description
  permissions = var.permissions
  stage       = var.stage
}

output "name" {
  description = "Fully-qualified custom role name."
  value       = google_project_iam_custom_role.this.name
}

output "role_id" {
  description = "Role ID of the custom role."
  value       = google_project_iam_custom_role.this.role_id
}

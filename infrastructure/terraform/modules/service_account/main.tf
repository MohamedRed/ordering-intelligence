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

resource "google_service_account" "this" {
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}

resource "google_project_iam_member" "service_account_roles" {
  # Use a map with stable integer keys so roles that are computed at apply-time (e.g., custom roles)
  # do not break plan-time validation of for_each keys.
  for_each = { for idx, role in var.project_roles : idx => role }

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.this.email}"
}

output "email" {
  description = "Email address for the created service account."
  value       = google_service_account.this.email
}

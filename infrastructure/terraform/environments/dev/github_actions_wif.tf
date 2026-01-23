locals {
  github_actions_repository = "MohamedRed/ordering-intelligence"
}

resource "google_iam_workload_identity_pool" "github_actions" {
  provider                  = google-beta
  project                   = local.project_number
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "OIDC pool for GitHub Actions."
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  provider                           = google-beta
  project                            = local.project_number
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"
  attribute_condition                = "assertion.repository == \"${local.github_actions_repository}\""

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

module "github_ci_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "github-ci-dev"
  display_name = "GitHub CI (dev)"
  description  = "GitHub Actions deployer for web integration smoke tests."
  project_roles = [
    "roles/datastore.user",
    "roles/firebase.admin",
    "roles/firebasehosting.admin",
    "roles/firebase.viewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/serviceusage.serviceUsageAdmin"
  ]
}

resource "google_service_account_iam_member" "github_ci_wif" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.github_ci_sa.email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.repository/${local.github_actions_repository}"
}

resource "google_service_account_iam_member" "github_ci_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.github_ci_sa.email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "principalSet://iam.googleapis.com/projects/${local.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.repository/${local.github_actions_repository}"
}

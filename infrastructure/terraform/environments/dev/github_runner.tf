locals {
  github_runner_repo  = "MohamedRed/ordering-intelligence"
  github_runner_zone  = "${var.region}-b"
  github_runner_name  = "github-runner-${var.environment_name}"
  github_runner_label = var.project_id
}

resource "google_secret_manager_secret" "github_actions_runner_pat" {
  project   = var.project_id
  secret_id = "github-actions-runner-pat"

  replication {
    auto {}
  }
}

module "github_runner_sa" {
  source       = "../../modules/service_account"
  project_id   = var.project_id
  account_id   = "github-runner-${var.environment_name}"
  display_name = "GitHub Runner (${var.environment_name})"
  description  = "Self-hosted GitHub Actions runner VM."
  project_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor"
  ]
}

resource "google_secret_manager_secret_iam_member" "github_runner_pat_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.github_actions_runner_pat.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.github_runner_sa.email}"
}

module "github_runner_vm" {
  source                = "../../modules/github_runner_vm"
  project_id            = var.project_id
  zone                  = local.github_runner_zone
  name                  = local.github_runner_name
  service_account_email = module.github_runner_sa.email
  network_self_link     = module.core.network_self_link
  subnetwork_self_link  = module.core.subnetwork_self_link
  runner_repo           = local.github_runner_repo
  runner_labels         = [local.github_runner_label]
  pat_secret_id         = google_secret_manager_secret.github_actions_runner_pat.secret_id
  labels = {
    env  = var.environment_name
    role = "github-runner"
  }

  depends_on = [
    module.github_runner_sa,
    google_secret_manager_secret_iam_member.github_runner_pat_access,
  ]
}

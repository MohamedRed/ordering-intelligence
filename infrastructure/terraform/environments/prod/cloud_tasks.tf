resource "google_cloud_tasks_queue" "ready_escalation" {
  name     = "ready-escalation-${var.environment_name}"
  project  = var.project_id
  location = var.region

  rate_limits {
    max_dispatches_per_second = 10
    max_concurrent_dispatches = 20
  }

  retry_config {
    max_attempts  = 5
    max_backoff   = "60s"
    min_backoff   = "5s"
    max_doublings = 5
  }
}

resource "google_cloud_tasks_queue" "dispatch_assignment" {
  name     = "dispatch-assignments-${var.environment_name}"
  project  = var.project_id
  location = var.region

  rate_limits {
    max_dispatches_per_second = 10
    max_concurrent_dispatches = 20
  }

  retry_config {
    max_attempts  = 5
    max_backoff   = "60s"
    min_backoff   = "5s"
    max_doublings = 5
  }
}

module "notification_tasks_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "notification-tasks-${var.environment_name}"
  display_name  = "Notification Tasks (${var.environment_name})"
  project_roles = []
}

module "dispatch_tasks_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "dispatch-tasks-${var.environment_name}"
  display_name  = "Dispatch Tasks (${var.environment_name})"
  project_roles = []
}

resource "google_service_account_iam_member" "cloudtasks_token_creator" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.notification_tasks_sa.email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${local.project_number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "cloudtasks_token_creator_dispatch" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.dispatch_tasks_sa.email}"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${local.project_number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "notification_service_act_as_tasks_sa" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.notification_tasks_sa.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.notification_service_sa.email}"
}

resource "google_service_account_iam_member" "dispatch_service_act_as_tasks_sa" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${module.dispatch_tasks_sa.email}"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${module.dispatch_service_sa.email}"
}

resource "google_cloud_scheduler_job" "menu_ingestion_cleanup" {
  name      = "menu-ingestion-cleanup"
  project   = var.project_id
  region    = var.region
  schedule  = "0 * * * *"
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "${local.service_urls.menu_ingestion}/tasks/cleanup"

    oidc_token {
      service_account_email = module.menu_ingestion_sa.email
    }
  }
}

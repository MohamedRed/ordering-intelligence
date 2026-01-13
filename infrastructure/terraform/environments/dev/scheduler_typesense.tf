resource "google_cloud_scheduler_job" "typesense_reconcile_nightly" {
  count     = var.typesense_host != "" ? 1 : 0
  name      = "typesense-reconcile-nightly-${var.environment_name}"
  project   = var.project_id
  region    = var.region
  schedule  = "0 2 * * *"
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "${local.service_urls.typesense_indexer}/tasks/sync"

    oidc_token {
      service_account_email = module.typesense_indexer_sa.email
    }
  }
}

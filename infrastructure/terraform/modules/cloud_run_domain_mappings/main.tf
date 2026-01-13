resource "google_cloud_run_domain_mapping" "this" {
  for_each = var.domains

  location = var.region
  name     = each.key

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = each.value
  }
}

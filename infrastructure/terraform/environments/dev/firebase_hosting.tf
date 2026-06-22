locals {
  firebase_hosting_sites = {
    admin    = "ordering-intelligence-dev-admin"
    business = "ordering-intelligence-dev-business"
    driver   = "ordering-intelligence-dev-driver"
    consumer = "ordering-intelligence-dev-consumer"
  }
}

resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
}

resource "google_firebase_hosting_site" "sites" {
  provider = google-beta
  for_each = local.firebase_hosting_sites

  project = var.project_id
  site_id = each.value

  depends_on = [google_firebase_project.default]
}

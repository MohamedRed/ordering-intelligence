resource "google_firebaserules_ruleset" "firestore_rules" {
  project = var.project_id

  source {
    files {
      name    = "firestore.rules"
      content = file("${path.module}/../../../..//backend/services/order-service/firestore.rules")
    }
  }
}

resource "google_firebaserules_release" "firestore_rules" {
  project      = var.project_id
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore_rules.name
}

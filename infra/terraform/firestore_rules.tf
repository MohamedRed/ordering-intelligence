resource "google_firestore_document" "firestore_rules_placeholder" {
  # Placeholder to keep module aware; actual rule deploy handled via CI/CLI.
  project = var.project_id
  collection = "__rules_placeholder__"
  document_id = "do-not-use"
  fields = {}
}

resource "google_firestore_index" "orders_store_created" {
  project     = var.project_id
  collection  = "orders"
  database    = "(default)"
  query_scope = "COLLECTION"

  fields {
    field_path = "storeId"
    order      = "ASCENDING"
  }

  fields {
    field_path = "createdAt"
    order      = "DESCENDING"
  }

  fields {
    field_path = "__name__"
    order      = "DESCENDING"
  }
}

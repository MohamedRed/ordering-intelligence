resource "google_firestore_index" "orders_store_created" {
  project     = var.project_id
  collection  = "orders"
  query_scope = "COLLECTION"

  fields {
    field_path = "storeId"
    order      = "ASCENDING"
  }

  fields {
    field_path = "createdAt"
    order      = "DESCENDING"
  }

  # Firestore requires __name__ for some composite indexes; include it to mirror the console-created index.
  fields {
    field_path = "__name__"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "marketplace_deliverers_active_available" {
  project     = var.project_id
  collection  = "marketplace_deliverers"
  query_scope = "COLLECTION"

  fields {
    field_path = "active"
    order      = "ASCENDING"
  }

  fields {
    field_path = "available"
    order      = "ASCENDING"
  }

  fields {
    field_path = "locationExpiresAt"
    order      = "ASCENDING"
  }

  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }
}

# TTL uses a field named expireAt; services should write this field.
resource "google_firestore_field" "orders_ttl" {
  project    = var.project_id
  database   = "(default)"
  collection = "orders"
  field      = "expireAt"

  ttl_config {
    state = "ENABLED"
  }
}

resource "google_firestore_field" "alerts_ttl" {
  project    = var.project_id
  database   = "(default)"
  collection = "alerts"
  field      = "expireAt"

  ttl_config {
    state = "ENABLED"
  }
}

resource "google_firestore_field" "idempotency_ttl" {
  project    = var.project_id
  database   = "(default)"
  collection = "idempotency_keys"
  field      = "expireAt"

  ttl_config {
    state = "ENABLED"
  }
}

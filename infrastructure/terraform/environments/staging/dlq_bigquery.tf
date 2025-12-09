resource "google_bigquery_dataset" "menu_ingest_dlq" {
  dataset_id = "menu_ingest_dlq"
  project    = var.project_id
  location   = var.region
}

resource "google_pubsub_subscription" "menu_ingest_dlq_bq" {
  name    = "menu-ingest-dlq-bq"
  topic   = google_pubsub_topic.menu_ingest_dlq.name
  project = var.project_id

  bigquery_config {
    table            = "${google_bigquery_dataset.menu_ingest_dlq.dataset_id}.messages"
    use_topic_schema = false
    write_metadata   = true
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"
}

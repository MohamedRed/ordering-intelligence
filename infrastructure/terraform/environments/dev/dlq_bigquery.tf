resource "google_bigquery_dataset" "menu_ingest_dlq" {
  dataset_id = "menu_ingest_dlq"
  project    = var.project_id
  location   = var.region

  access {
    role          = "WRITER"
    user_by_email = "service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  }

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role          = "OWNER"
    user_by_email = "livvemap@gmail.com"
  }
}

resource "google_bigquery_table" "menu_ingest_dlq_messages" {
  dataset_id          = google_bigquery_dataset.menu_ingest_dlq.dataset_id
  project             = var.project_id
  table_id            = "messages"
  deletion_protection = false

  schema = jsonencode([
    { "name" : "data", "type" : "BYTES", "mode" : "NULLABLE" },
    { "name" : "attributes", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "message_id", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "publish_time", "type" : "TIMESTAMP", "mode" : "NULLABLE" },
    { "name" : "ordering_key", "type" : "STRING", "mode" : "NULLABLE" },
    { "name" : "delivery_attempt", "type" : "INTEGER", "mode" : "NULLABLE" },
    { "name" : "subscription_name", "type" : "STRING", "mode" : "NULLABLE" }
  ])
}

resource "google_pubsub_subscription" "menu_ingest_dlq_bq" {
  name    = "menu-ingest-dlq-bq"
  topic   = google_pubsub_topic.menu_ingest_dlq.name
  project = var.project_id

  bigquery_config {
    table            = "${var.project_id}:${google_bigquery_dataset.menu_ingest_dlq.dataset_id}.messages"
    use_topic_schema = false
    write_metadata   = true
  }

  ack_deadline_seconds       = 20
  message_retention_duration = "1200s"
}

resource "google_pubsub_topic" "orders_dlq" {
  name = "orders-dlq"
}

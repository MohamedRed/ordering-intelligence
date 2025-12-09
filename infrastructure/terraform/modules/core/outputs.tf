output "network_name" {
  description = "Name of the core VPC network."
  value       = google_compute_network.core.name
}

output "firestore_database" {
  description = "Firestore database resource name."
  value       = google_firestore_database.default.name
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository for container images."
  value       = google_artifact_registry_repository.services.repository_id
}

output "pubsub_topics" {
  description = "Map of Pub/Sub topics created."
  value       = { for k, topic in google_pubsub_topic.topics : k => topic.name }
}

output "secret_manager_secrets" {
  description = "Secret Manager secret IDs."
  value       = [for secret in google_secret_manager_secret.secrets : secret.secret_id]
}

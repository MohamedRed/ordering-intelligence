output "network_name" {
  description = "Name of the core VPC network."
  value       = google_compute_network.core.name
}

output "network_self_link" {
  description = "Self link of the core VPC network."
  value       = google_compute_network.core.self_link
}

output "subnetwork_self_link" {
  description = "Self link of the core subnetwork."
  value       = google_compute_subnetwork.core.self_link
}

output "network_id" {
  description = "VPC network resource ID in projects/*/global/networks/* format (required by some APIs)."
  value       = google_compute_network.core.id
}

output "subnetwork_id" {
  description = "Subnetwork resource ID in projects/*/regions/*/subnetworks/* format (required by some APIs)."
  value       = google_compute_subnetwork.core.id
}

output "serverless_vpc_connector_id" {
  description = "ID/self_link of the Serverless VPC Access connector (null if disabled)."
  value       = try(google_vpc_access_connector.serverless[0].id, null)
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

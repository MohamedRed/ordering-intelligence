output "uri" {
  description = "The service URI."
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  description = "The Cloud Run service name."
  value       = google_cloud_run_v2_service.this.name
}



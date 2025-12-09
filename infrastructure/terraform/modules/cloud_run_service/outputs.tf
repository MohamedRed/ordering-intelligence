output "service_name" {
  description = "Name of the Cloud Run service."
  value       = google_cloud_run_service.this.name
}

output "service_url" {
  description = "Primary URL for the Cloud Run service."
  value       = try(google_cloud_run_service.this.status[0].url, null)
}

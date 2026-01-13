output "resource_records" {
  description = "DNS records required to validate the Cloud Run domain mappings."
  value = {
    for domain, mapping in google_cloud_run_domain_mapping.this :
    domain => mapping.status[0].resource_records
  }
}

output "domains" {
  description = "Domains mapped to Cloud Run services."
  value       = keys(var.domains)
}

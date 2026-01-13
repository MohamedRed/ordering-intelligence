output "name_servers" {
  description = "Authoritative name servers for the managed zone."
  value       = try(google_dns_managed_zone.this[0].name_servers, [])
}

output "zone_name" {
  description = "Managed zone name."
  value       = try(google_dns_managed_zone.this[0].name, "")
}

output "record_sets" {
  description = "DNS record sets created for mapped domains."
  value       = local.record_sets
}

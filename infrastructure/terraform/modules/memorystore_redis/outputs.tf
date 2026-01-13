output "host" {
  description = "Redis host."
  value       = google_redis_instance.this.host
}

output "port" {
  description = "Redis port."
  value       = google_redis_instance.this.port
}

output "instance_id" {
  description = "Redis instance ID."
  value       = google_redis_instance.this.id
}



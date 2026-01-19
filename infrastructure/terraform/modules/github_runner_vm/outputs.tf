output "instance_name" {
  description = "Runner VM instance name."
  value       = google_compute_instance.runner.name
}

output "instance_self_link" {
  description = "Runner VM instance self link."
  value       = google_compute_instance.runner.self_link
}

output "internal_ip" {
  description = "Runner VM internal IP."
  value       = google_compute_instance.runner.network_interface[0].network_ip
}

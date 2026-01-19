resource "google_compute_firewall" "github_runner_iap_ssh" {
  name    = "github-runner-iap-ssh-${var.environment_name}"
  project = var.project_id
  network = module.core.network_self_link

  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  target_service_accounts = [module.github_runner_sa.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

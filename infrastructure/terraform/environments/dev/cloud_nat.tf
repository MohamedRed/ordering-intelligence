resource "google_compute_router" "core_nat_router" {
  name    = "core-nat-${var.environment_name}"
  project = var.project_id
  region  = var.region
  network = module.core.network_self_link
}

resource "google_compute_router_nat" "core_nat" {
  name                               = "core-nat-${var.environment_name}"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.core_nat_router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

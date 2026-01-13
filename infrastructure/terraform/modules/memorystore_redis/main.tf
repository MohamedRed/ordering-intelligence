resource "google_compute_global_address" "private_service_range" {
  count = var.enable_private_service_access ? 1 : 0

  project       = var.project_id
  name          = var.private_service_access_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_access_prefix_length
  network       = var.network_self_link
}

resource "google_service_networking_connection" "private_service_connection" {
  count = var.enable_private_service_access ? 1 : 0

  network                 = var.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range[0].name]
}

resource "google_redis_instance" "this" {
  project        = var.project_id
  region         = var.region
  name           = var.name
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  redis_version  = var.redis_version

  authorized_network = var.network_self_link

  // Prefer simple network-based isolation; AUTH can be enabled later if needed.
  transit_encryption_mode = "DISABLED"

  depends_on = [google_service_networking_connection.private_service_connection]
}



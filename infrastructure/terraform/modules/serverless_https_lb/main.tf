terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

locals {
  certificate_mode = upper(var.certificate_mode)
  use_self_signed  = local.certificate_mode == "SELF_SIGNED"
}

resource "google_compute_region_network_endpoint_group" "cloud_run_neg" {
  name                  = "${var.environment_name}-${var.cloud_run_service}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = var.cloud_run_service
  }
}

resource "google_compute_global_address" "this" {
  name = "${var.environment_name}-${var.cloud_run_service}-lb-ip"
}

locals {
  default_managed_domains = [
    format(
      "%s-%s.%s.nip.io",
      var.environment_name,
      var.cloud_run_service,
      replace(google_compute_global_address.this.address, ".", "-")
    )
  ]

  effective_managed_domains = length(var.managed_domains) > 0 ? var.managed_domains : local.default_managed_domains

  managed_cert_name = format(
    "%s-%s-%s-managed",
    var.environment_name,
    var.cloud_run_service,
    substr(sha1(join(",", local.effective_managed_domains)), 0, 8)
  )
}

resource "tls_private_key" "self_signed" {
  count     = local.use_self_signed ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count                 = local.use_self_signed ? 1 : 0
  private_key_pem       = tls_private_key.self_signed[0].private_key_pem
  validity_period_hours = var.certificate_validity_hours

  subject {
    common_name  = var.hostname
    organization = "Ordering Intelligence"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

resource "google_compute_ssl_certificate" "self_signed" {
  count       = local.use_self_signed ? 1 : 0
  name        = "${var.environment_name}-${var.cloud_run_service}-selfsigned"
  certificate = tls_self_signed_cert.self_signed[0].cert_pem
  private_key = tls_private_key.self_signed[0].private_key_pem
}

resource "google_compute_managed_ssl_certificate" "managed" {
  count = local.use_self_signed ? 0 : 1
  name  = local.managed_cert_name

  managed {
    domains = local.effective_managed_domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_backend_service" "this" {
  name                  = "${var.environment_name}-${var.cloud_run_service}-backend"
  project               = var.project_id
  # Cloud Run serverless NEGs are reached over HTTP from the load balancer.
  # Using HTTPS here can cause unexpected edge errors (e.g., 403) depending on backend integration.
  protocol              = "HTTP"
  timeout_sec           = var.backend_timeout_seconds
  load_balancing_scheme = "EXTERNAL"
  security_policy       = var.security_policy_id != null && var.security_policy_id != "" ? var.security_policy_id : null

  backend {
    group = google_compute_region_network_endpoint_group.cloud_run_neg.id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "this" {
  name            = "${var.environment_name}-${var.cloud_run_service}-urlmap"
  default_service = google_compute_backend_service.this.id
}

resource "google_compute_target_https_proxy" "this" {
  name    = "${var.environment_name}-${var.cloud_run_service}-https-proxy"
  url_map = google_compute_url_map.this.id
  ssl_certificates = local.use_self_signed ? [
    google_compute_ssl_certificate.self_signed[0].self_link
    ] : [
    google_compute_managed_ssl_certificate.managed[0].self_link
  ]
}

resource "google_compute_global_forwarding_rule" "this" {
  name                  = "${var.environment_name}-${var.cloud_run_service}-https-fr"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  ip_protocol           = "TCP"
  target                = google_compute_target_https_proxy.this.id
  ip_address            = google_compute_global_address.this.address
}

output "ip_address" {
  description = "Reserved global IP address for the HTTPS load balancer."
  value       = google_compute_global_address.this.address
}

output "hostname" {
  description = "Logical hostname associated with the certificate CN."
  value       = local.use_self_signed ? var.hostname : local.effective_managed_domains[0]
}

output "certificate_pem" {
  description = "Self-signed certificate PEM (for pinning / curl verification)."
  value       = local.use_self_signed ? tls_self_signed_cert.self_signed[0].cert_pem : null
  sensitive   = true
}

output "managed_domains" {
  description = "Managed certificate domains (if applicable)."
  value       = local.use_self_signed ? [] : local.effective_managed_domains
}

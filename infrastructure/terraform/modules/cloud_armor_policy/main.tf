terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

resource "google_compute_security_policy" "this" {
  count       = var.enabled ? 1 : 0
  name        = var.policy_name
  description = var.description

  dynamic "rule" {
    for_each = length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      action      = "allow"
      priority    = 900
      description = "IP allowlist"

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.allowed_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = length(var.blocked_ip_ranges) > 0 ? [1] : []
    content {
      action      = "deny(403)"
      priority    = 1000
      description = "Static block list"

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.blocked_ip_ranges
        }
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_rate_limit ? [1] : []
    content {
      action      = "throttle"
      priority    = 2000
      description = "Per-IP rate limiting"

      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = length(var.allowed_ip_ranges) > 0 ? var.allowed_ip_ranges : ["*"]
        }
      }

      rate_limit_options {
        rate_limit_threshold {
          count        = var.rate_limit_threshold
          interval_sec = var.rate_limit_interval_seconds
        }

        conform_action = "allow"
        exceed_action  = "deny(429)"
      }
    }
  }

  rule {
    action      = length(var.allowed_ip_ranges) > 0 ? "deny(403)" : "allow"
    priority    = 2147483647
    description = length(var.allowed_ip_ranges) > 0 ? "Default deny (allowlist enabled)" : "Default allow"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

output "policy_id" {
  description = "ID of the Cloud Armor security policy."
  value       = try(google_compute_security_policy.this[0].id, null)
}

output "policy_name" {
  description = "Name of the security policy."
  value       = try(google_compute_security_policy.this[0].name, null)
}

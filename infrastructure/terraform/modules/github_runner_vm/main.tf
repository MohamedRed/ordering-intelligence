terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

locals {
  runner_labels_csv = join(",", var.runner_labels)
}

resource "google_compute_instance" "runner" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone

  tags   = var.network_tags
  labels = var.labels

  boot_disk {
    initialize_params {
      image = var.base_image
      size  = 100
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = var.subnetwork_self_link
  }

  service_account {
    email  = var.service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/startup.sh.tftpl", {
    runner_version = var.runner_version
    repo_name      = var.runner_repo
    runner_name    = var.name
    runner_labels  = local.runner_labels_csv
    pat_secret_id  = var.pat_secret_id
  })

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

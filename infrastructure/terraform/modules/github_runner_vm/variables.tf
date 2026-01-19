variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "zone" {
  type        = string
  description = "GCP zone to deploy the runner VM."
}

variable "name" {
  type        = string
  description = "Compute instance name."
}

variable "machine_type" {
  type        = string
  description = "Compute instance machine type."
  default     = "e2-standard-4"
}

variable "service_account_email" {
  type        = string
  description = "Service account email for the runner VM."
}

variable "network_self_link" {
  type        = string
  description = "VPC network self link."
}

variable "subnetwork_self_link" {
  type        = string
  description = "Subnetwork self link."
}

variable "runner_repo" {
  type        = string
  description = "GitHub repo in org/name format."
}

variable "runner_labels" {
  type        = list(string)
  description = "Extra labels to register on the runner."
  default     = []
}

variable "pat_secret_id" {
  type        = string
  description = "Secret Manager secret ID that stores a GitHub PAT."
}

variable "runner_version" {
  type        = string
  description = "GitHub Actions runner version to install."
  default     = "2.316.1"
}

variable "base_image" {
  type        = string
  description = "Base image for the runner VM."
  default     = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

variable "network_tags" {
  type        = list(string)
  description = "Network tags for the runner VM."
  default     = []
}

variable "labels" {
  type        = map(string)
  description = "Compute instance labels."
  default     = {}
}

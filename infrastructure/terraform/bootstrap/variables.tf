variable "project_id" {
  description = "New GCP project ID to create (must be globally unique)."
  type        = string
}

variable "project_name" {
  description = "Display name for the project."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID to link (e.g., 013632-2013D4-83320F)."
  type        = string
}

variable "org_id" {
  description = "Organization ID. Required if folder_id is empty."
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID to place the project under. Leave empty to use org_id."
  type        = string
  default     = ""
}

variable "enable_apis" {
  description = "Minimal set of APIs to enable for the project."
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
  ]
}

variable "project_labels" {
  description = "Labels to apply to the project."
  type        = map(string)
  default     = { environment = "dev" }
}

variable "default_region" {
  description = "Default region for provider (not used for project creation but required)."
  type        = string
  default     = "us-central1"
}

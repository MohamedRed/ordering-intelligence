variable "project_id" {
  description = "GCP project ID hosting the Cloud Run services."
  type        = string
}

variable "region" {
  description = "Cloud Run region for domain mappings."
  type        = string
}

variable "domains" {
  description = "Map of fully-qualified domains to Cloud Run service names."
  type        = map(string)
  default     = {}
}

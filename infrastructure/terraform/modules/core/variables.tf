variable "project_id" {
  description = "GCP project identifier."
  type        = string
}

variable "region" {
  description = "Primary deployment region (e.g., us-central1)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID for project linkage."
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Name for the shared VPC network."
  type        = string
  default     = "ordering-intelligence-core"
}

variable "subnet_cidr_range" {
  description = "CIDR range for the core subnet."
  type        = string
  default     = "10.10.0.0/24"
}

variable "firestore_location" {
  description = "Location/region for Firestore database (e.g., nam5)."
  type        = string
  default     = "nam5"
}

variable "bigquery_location" {
  description = "Location for BigQuery datasets."
  type        = string
  default     = "US"
}

variable "pubsub_topics" {
  description = "List of Pub/Sub topics to create."
  type        = list(string)
  default = [
    "orders-events",
    "call-transcripts",
    "alerts-events",
    "dispatch-events",
    "deliveries-events"
  ]
}

variable "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository for service images."
  type        = string
  default     = "services"
}

variable "artifact_registry_format" {
  description = "Artifact Registry format (default docker)."
  type        = string
  default     = "DOCKER"
}

variable "secret_names" {
  description = "Secret Manager secret IDs to provision."
  type        = list(string)
  default = [
    "twilio-auth-token",
    "livekit-api-key",
    "livekit-api-secret",
    "llm-provider-api-key"
  ]
}

variable "run_service_accounts" {
  description = "Service account emails to grant Secret Manager accessor rights for Cloud Run services."
  type        = list(string)
  default     = []
}

variable "enable_services" {
  description = "List of Google APIs to enable on the project."
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "run.googleapis.com",
    "firestore.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "iamcredentials.googleapis.com",
    "vision.googleapis.com",
    "aiplatform.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "redis.googleapis.com",
    "recaptchaenterprise.googleapis.com"
  ]
}

variable "serverless_vpc_connector_name" {
  description = "Name of the Serverless VPC Access connector."
  type        = string
  default     = "serverless-connector"
}

variable "serverless_vpc_connector_cidr" {
  description = "CIDR range for the Serverless VPC Access connector (must not overlap subnet ranges)."
  type        = string
  default     = "10.8.0.0/28"
}

variable "enable_serverless_vpc_connector" {
  description = "Whether to create a Serverless VPC Access connector in the core network."
  type        = bool
  default     = false
}

variable "analytics_dataset_id" {
  description = "Canonical dataset ID for analytics exports."
  type        = string
  default     = "ordering_analytics"
}

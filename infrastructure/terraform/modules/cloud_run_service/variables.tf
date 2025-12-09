variable "project_id" {
  description = "GCP project that hosts the Cloud Run service."
  type        = string
}

variable "location" {
  description = "Region for the Cloud Run service (e.g., us-central1)."
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service."
  type        = string
}

variable "image" {
  description = "Container image to deploy."
  type        = string
}

variable "min_scale" {
  description = "Minimum number of container instances."
  type        = number
  default     = 0
}

variable "max_scale" {
  description = "Maximum number of container instances."
  type        = number
  default     = 20
}

variable "container_concurrency" {
  description = "Maximum number of concurrent requests per container instance."
  type        = number
  default     = 80
}

variable "timeout_seconds" {
  description = "Request timeout in seconds."
  type        = number
  default     = 300
}

variable "cpu" {
  description = "CPU limit for the container (e.g., 1000m)."
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory limit for the container (e.g., 512Mi)."
  type        = string
  default     = "512Mi"
}

variable "service_account" {
  description = "Service account email for the Cloud Run service. Leave null to use the default compute service account."
  type        = string
  default     = null
}

variable "ingress" {
  description = "Ingress setting for the Cloud Run service (all/internal/internal-and-cloud-load-balancing)."
  type        = string
  default     = "all"
}

variable "labels" {
  description = "Labels to attach to the Cloud Run service."
  type        = map(string)
  default     = {}
}

variable "env_vars" {
  description = "Plain environment variables to inject into the container."
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = "Mapping of environment variable names to Secret Manager secret IDs (latest version will be used)."
  type        = map(string)
  default     = {}
}

variable "secret_version" {
  description = "Secret Manager version to mount for secret environment variables."
  type        = string
  default     = "latest"
}

variable "startup_cpu_boost" {
  description = "Whether to enable Cloud Run startup CPU boost."
  type        = bool
  default     = true
}

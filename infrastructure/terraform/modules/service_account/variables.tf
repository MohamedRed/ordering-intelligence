variable "project_id" {
  description = "Project that will own the service account."
  type        = string
}

variable "account_id" {
  description = "Service account ID (must be unique within the project)."
  type        = string
}

variable "display_name" {
  description = "Display name for the service account."
  type        = string
}

variable "description" {
  description = "Optional description for the service account."
  type        = string
  default     = ""
}

variable "project_roles" {
  description = "List of project-level IAM roles to bind to the service account."
  type        = list(string)
  default     = []
}

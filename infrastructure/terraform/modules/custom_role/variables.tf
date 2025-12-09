variable "project_id" {
  description = "Project where the custom role is created."
  type        = string
}

variable "role_id" {
  description = "Custom role ID (letters, numbers, underscores)."
  type        = string
}

variable "title" {
  description = "Display title for the custom role."
  type        = string
}

variable "description" {
  description = "Description of the custom role."
  type        = string
  default     = ""
}

variable "permissions" {
  description = "List of permissions granted by the custom role."
  type        = list(string)
}

variable "stage" {
  description = "Launch stage for the custom role."
  type        = string
  default     = "GA"
}

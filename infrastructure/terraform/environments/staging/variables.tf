variable "project_id" {
  description = "GCP project ID for the environment."
  type        = string
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "us-central1"
}

variable "firestore_location" {
  description = "Firestore database location (multi-region), e.g. nam5."
  type        = string
  default     = "nam5"
}

variable "typesense_host" {
  description = "Typesense Cloud host (without protocol). Leave empty to disable indexing."
  type        = string
  default     = ""
}

variable "environment_name" {
  description = "Identifier for the deployment environment (e.g., staging)."
  type        = string
  default     = "staging"
}

variable "billing_account" {
  description = "Billing account for project creation (optional)."
  type        = string
  default     = ""
}

variable "image_registry_project" {
  description = "GCP project that hosts shared container images (default uses this environment's project)."
  type        = string
  default     = ""
}

variable "custom_domain_base" {
  description = "Base DNS zone for custom service domains (e.g. liive.app). Leave empty to keep run.app URLs."
  type        = string
  default     = ""
}

variable "custom_domain_prefix" {
  description = "Optional prefix for custom service domains (defaults to env name with a trailing hyphen, except prod)."
  type        = string
  default     = ""
}

variable "custom_domain_service_keys" {
  description = "Optional list of service keys to receive custom domains. Leave empty to use the default set."
  type        = list(string)
  default     = []
}

variable "custom_service_domain_overrides" {
  description = "Optional per-service domain overrides (map of service key to domain)."
  type        = map(string)
  default     = {}
}

variable "enable_cloud_dns" {
  description = "When true, create a Cloud DNS zone and manage records for Cloud Run domain mappings."
  type        = bool
  default     = false
}

variable "enable_cloud_run_domain_mappings" {
  description = "When true, create Cloud Run domain mappings for custom domains."
  type        = bool
  default     = true
}

variable "cloud_dns_zone_name" {
  description = "Managed zone name for Cloud DNS (must be unique within the project)."
  type        = string
  default     = "liive-app"
}

variable "cloud_dns_domain" {
  description = "Base DNS domain for the managed zone (defaults to custom_domain_base)."
  type        = string
  default     = ""
}

variable "cloud_run_overrides" {
  description = "Optional per-service overrides for Cloud Run runtime settings and environment variables."
  type = map(object({
    min_scale             = optional(number)
    max_scale             = optional(number)
    container_concurrency = optional(number)
    timeout_seconds       = optional(number)
    cpu                   = optional(string)
    memory                = optional(string)
    startup_cpu_boost     = optional(bool)
    env_overrides         = optional(map(string))
    secret_env_overrides  = optional(map(string))
  }))
  default = {}
}

variable "admin_service_cors_origins" {
  description = "Explicit browser origins allowed to call admin-service. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.admin_service_cors_origins) > 0 && !contains(var.admin_service_cors_origins, "*")
    error_message = "admin_service_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "agent_customization_cors_origins" {
  description = "Explicit browser origins allowed to call agent-customization. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.agent_customization_cors_origins) > 0 && !contains(var.agent_customization_cors_origins, "*")
    error_message = "agent_customization_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "onboarding_cors_origins" {
  description = "Explicit browser origins allowed to call onboarding-service. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.onboarding_cors_origins) > 0 && !contains(var.onboarding_cors_origins, "*")
    error_message = "onboarding_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "notification_service_cors_origins" {
  description = "Explicit browser origins allowed to call notification-service. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.notification_service_cors_origins) > 0 && !contains(var.notification_service_cors_origins, "*")
    error_message = "notification_service_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "dispatch_service_cors_origins" {
  description = "Explicit browser origins allowed to call dispatch-service. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.dispatch_service_cors_origins) > 0 && !contains(var.dispatch_service_cors_origins, "*")
    error_message = "dispatch_service_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "delivery_service_cors_origins" {
  description = "Explicit browser origins allowed to call delivery-service. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition     = length(var.delivery_service_cors_origins) > 0 && !contains(var.delivery_service_cors_origins, "*")
    error_message = "delivery_service_cors_origins must contain at least one explicit origin and cannot include '*'."
  }
}

variable "channel_gateway_cors_origins" {
  description = "Explicit browser origins allowed to call channel-gateway. Wildcards are not allowed."
  type        = list(string)

  validation {
    condition = length(var.channel_gateway_cors_origins) > 0 && alltrue([
      for origin in var.channel_gateway_cors_origins : trimspace(origin) != "" && !can(regex("\\*", origin))
    ])
    error_message = "channel_gateway_cors_origins must contain at least one explicit origin and cannot include wildcards or blank values."
  }
}

variable "agent_tools_gemini_model" {
  description = "Vertex AI Gemini model ID/path for agent-tools (leave empty to disable LLM script generation)."
  type        = string
  default     = ""
}

variable "enable_agent_tools_redis_cache" {
  description = "When true, provision Memorystore Redis and wire agent-tools to use it for voice menu caching."
  type        = bool
  default     = false
}

variable "agent_tools_redis_memory_gb" {
  description = "Memorystore Redis memory size for agent-tools voice menu cache."
  type        = number
  default     = 1
}

variable "waf_blocked_ip_ranges" {
  description = "Optional static IP ranges to block at the Cloud Armor policy."
  type        = list(string)
  default     = []
}

variable "order_service_lb_hostname" {
  description = "Logical hostname used for the staging order service load balancer certificate."
  type        = string
  default     = "order-service-staging.local"
}

variable "order_service_lb_certificate_mode" {
  description = "Certificate mode for the staging load balancer (SELF_SIGNED or MANAGED)."
  type        = string
  default     = "SELF_SIGNED"
}

variable "order_service_lb_managed_domains" {
  description = "Optional explicit domains for managed certificates (defaults to nip.io domain)."
  type        = list(string)
  default     = []
}

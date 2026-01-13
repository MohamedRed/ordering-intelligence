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
  description = "Identifier for the deployment environment (e.g., dev)."
  type        = string
  default     = "dev"
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

# Dev-only toggle: ElevenLabs egress IP allowlist can be brittle if their outbound IPs change
# or if the integration isn't actually coming from those IPs. When disabled, Cloud Armor
# will default-allow but still apply rate limiting.
variable "enable_elevenlabs_ip_allowlist" {
  description = "When true, Cloud Armor will allow only the configured ElevenLabs egress IPs (default deny all others). Dev-only."
  type        = bool
  default     = false
}

variable "enable_cloud_armor" {
  description = "When true, create Cloud Armor WAF policies and attach them to the agent-tools/agent-webhooks load balancers."
  type        = bool
  default     = false
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

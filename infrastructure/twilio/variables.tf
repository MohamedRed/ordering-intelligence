variable "environment" {
  description = "Short environment slug (dev/staging/prod)."
  type        = string
}

variable "twilio_account_sid" {
  description = "Twilio Account SID used for API authentication."
  type        = string
  sensitive   = true
}

variable "twilio_auth_token" {
  description = "Twilio Auth Token used for API authentication."
  type        = string
  sensitive   = true
}

variable "friendly_name_prefix" {
  description = "Prefix used for friendly names (defaults to 'oi')."
  type        = string
  default     = null
}

variable "livekit_sip_subdomain" {
  description = "LiveKit SIP subdomain (e.g. ordering-intelligence-dev)."
  type        = string
}

variable "livekit_sip_region" {
  description = "LiveKit SIP region (e.g. us, eu, india)."
  type        = string
}

variable "enable_secure_trunking" {
  description = "If true, enforces TLS/SRTP on the Twilio SIP trunk."
  type        = bool
  default     = true
}

variable "enable_sip_refer" {
  description = "Enable SIP REFER / PSTN transfer on the trunk."
  type        = bool
  default     = true
}

variable "enable_trunk_recording" {
  description = "Toggle Twilio SIP trunk recording for compliance."
  type        = bool
  default     = false
}

variable "termination_allowed_cidrs" {
  description = "List of CIDR ranges permitted to terminate calls to Twilio."
  type        = list(string)
  default     = []
}

variable "inbound_phone_numbers" {
  description = "Map of DID label -> Twilio phone SID to attach to the inbound trunk."
  type        = map(string)
  default     = {}
}

variable "fallback_targets" {
  description = <<EOF
Optional list of fallback targets when LiveKit is unavailable. Each entry is an object
with keys: target (SIP URI), priority (default 10), weight (default 1).
EOF
  type = list(object({
    target   = string
    priority = optional(number)
    weight   = optional(number)
  }))
  default = []
}

variable "enable_outbound_trunk" {
  description = "Create a separate Twilio SIP trunk for outbound / PSTN transfer."
  type        = bool
  default     = false
}

variable "create_credential_list" {
  description = "Create SIP credential list + credential for LiveKit registration."
  type        = bool
  default     = false
}

variable "sip_username" {
  description = "SIP credential username (required if create_credential_list=true)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "sip_password" {
  description = "SIP credential password (required if create_credential_list=true)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "inbound_sip_domain" {
  description = "Override for the Twilio SIP termination domain (optional)."
  type        = string
  default     = ""
}


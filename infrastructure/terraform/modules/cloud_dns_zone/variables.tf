variable "project_id" {
  description = "GCP project ID hosting the Cloud DNS zone."
  type        = string
}

variable "zone_name" {
  description = "Managed zone name."
  type        = string
}

variable "domain" {
  description = "Base DNS zone domain (e.g. liive.app)."
  type        = string
  default     = ""
}

variable "description" {
  description = "Optional managed zone description."
  type        = string
  default     = ""
}

variable "enabled" {
  description = "When false, no DNS resources are created."
  type        = bool
  default     = false
}

variable "ttl" {
  description = "Default TTL for DNS record sets."
  type        = number
  default     = 300
}

variable "resource_records" {
  description = "Cloud Run domain mapping resource records keyed by domain."
  type        = any
  default     = {}
}

variable "expected_record_types" {
  description = "Expected DNS record types per domain (e.g. {\"admin.dev.liive.app\"=[\"CNAME\"]})."
  type        = map(list(string))
  default     = {}
}

variable "extra_records" {
  description = "Additional DNS records to create (e.g. load balancer A records)."
  type = list(object({
    name    = string
    type    = string
    rrdatas = list(string)
    ttl     = optional(number)
  }))
  default = []
}

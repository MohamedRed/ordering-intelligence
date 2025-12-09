terraform {
  required_version = ">= 1.5.0"

  required_providers {
    twilio = {
      source  = "twilio-labs/twilio"
      version = "~> 0.14"
    }
  }
}

provider "twilio" {
  account_sid = var.twilio_account_sid
  auth_token  = var.twilio_auth_token
}

locals {
  env_suffix        = var.environment
  friendly_prefix   = coalesce(var.friendly_name_prefix, "oi")
  inbound_domain    = var.inbound_sip_domain != "" ? var.inbound_sip_domain : "oi-${local.env_suffix}"
  connection_policy = "${local.friendly_prefix}-${local.env_suffix}-livekit"
}

# Inbound SIP trunk routing calls into LiveKit.
resource "twilio_sip_trunk" "inbound" {
  friendly_name    = "${local.friendly_prefix}-${local.env_suffix}-inbound"
  secure_trunking  = var.enable_secure_trunking
  recording        = var.enable_trunk_recording ? "required" : "disabled"
  transfer_enabled = var.enable_sip_refer

  termination {
    sip_cidr_list = var.termination_allowed_cidrs
    domain        = "${local.inbound_domain}.pstn.twilio.com"
  }

  origination {
    enabled  = true
    url      = "sip:${var.livekit_sip_subdomain}.${var.livekit_sip_region}.sip.livekit.cloud"
    protocol = var.enable_secure_trunking ? "tls" : "udp"
  }
}

# Optional outbound trunk handed to LiveKit for PSTN transfer / REFER.
resource "twilio_sip_trunk" "outbound" {
  count = var.enable_outbound_trunk ? 1 : 0

  friendly_name    = "${local.friendly_prefix}-${local.env_suffix}-outbound"
  secure_trunking  = var.enable_secure_trunking
  transfer_enabled = var.enable_sip_refer

  termination {
    sip_cidr_list = var.termination_allowed_cidrs
  }

  origination {
    enabled  = true
    url      = "sip:${var.livekit_sip_subdomain}.${var.livekit_sip_region}.sip.livekit.cloud"
    protocol = var.enable_secure_trunking ? "tls" : "udp"
  }
}

# Connection policy used by <Dial><Sip> apps and Twilio Client to reach LiveKit.
resource "twilio_sip_connection_policy" "livekit" {
  friendly_name = local.connection_policy
}

resource "twilio_sip_connection_policy_target" "livekit_default" {
  policy_sid = twilio_sip_connection_policy.livekit.sid

  friendly_name = "LiveKit ${var.livekit_sip_region}"
  priority      = 1
  weight        = 1
  enabled       = true
  target        = "sip:${var.livekit_sip_subdomain}.${var.livekit_sip_region}.sip.livekit.cloud"
}

# Credential list that LiveKit uses when registering to Twilio (optional).
resource "twilio_sip_credential_list" "livekit" {
  count = var.create_credential_list ? 1 : 0

  friendly_name = "${local.friendly_prefix}-${local.env_suffix}-sip-creds"
}

resource "twilio_sip_credential" "livekit" {
  count = var.create_credential_list ? 1 : 0

  credential_list_sid = twilio_sip_credential_list.livekit[0].sid
  username            = var.sip_username
  password            = var.sip_password
}

resource "twilio_sip_trunk_credential_list_mapping" "inbound_credentials" {
  count = var.create_credential_list ? 1 : 0

  trunk_sid           = twilio_sip_trunk.inbound.sid
  credential_list_sid = twilio_sip_credential_list.livekit[0].sid
}

resource "twilio_sip_trunk_credential_list_mapping" "outbound_credentials" {
  count = var.enable_outbound_trunk && var.create_credential_list ? 1 : 0

  trunk_sid           = twilio_sip_trunk.outbound[0].sid
  credential_list_sid = twilio_sip_credential_list.livekit[0].sid
}

resource "twilio_sip_trunk_origination_url" "fallback" {
  count = length(var.fallback_targets)

  trunk_sid = twilio_sip_trunk.inbound.sid
  priority  = lookup(var.fallback_targets[count.index], "priority", 10)
  weight    = lookup(var.fallback_targets[count.index], "weight", 1)
  enabled   = true
  sip_url   = lookup(var.fallback_targets[count.index], "target", "sip:${var.livekit_sip_subdomain}.${var.livekit_sip_region}.sip.livekit.cloud")
}

resource "twilio_sip_trunk_phone_number" "did_mappings" {
  for_each = var.inbound_phone_numbers

  trunk_sid = twilio_sip_trunk.inbound.sid
  phone_sid = each.value
}


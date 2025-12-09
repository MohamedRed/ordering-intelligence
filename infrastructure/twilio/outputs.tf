output "inbound_trunk_sid" {
  description = "SID for the inbound SIP trunk."
  value       = twilio_sip_trunk.inbound.sid
}

output "outbound_trunk_sid" {
  description = "SID for the optional outbound SIP trunk."
  value       = try(twilio_sip_trunk.outbound[0].sid, null)
}

output "connection_policy_sid" {
  description = "SID for the LiveKit connection policy."
  value       = twilio_sip_connection_policy.livekit.sid
}

output "credential_list_sid" {
  description = "SID for the LiveKit SIP credential list (if created)."
  value       = try(twilio_sip_credential_list.livekit[0].sid, null)
}


output "dashboard_ids" {
  description = "Monitoring dashboard resource IDs."
  value       = [for d in google_monitoring_dashboard.dashboards : d.id]
}

output "alert_policy_ids" {
  description = "Alert policy IDs provisioned by the module."
  value = [
    for policy in concat(
      tolist(google_monitoring_alert_policy.telephony_5xx),
      tolist(google_monitoring_alert_policy.orchestrator_latency)
    ) : policy.id
    if policy.id != ""
  ]
}

output "notification_channel_ids" {
  description = "Email notification channel IDs created by the module."
  value       = [for channel in google_monitoring_notification_channel.email : channel.id]
}

# Incident Response Runbook

## Activation
- Alerts originate from Cloud Monitoring or LiveKit Cloud (SIP dispatch failures, voice agent errors, order-service 5xx) to Slack/PagerDuty via notification channels.
- First responder acknowledges alert in PagerDuty and communicates status in `#ops-oncall` Slack channel.

## Initial Assessment
1. Review dashboard for impacted service (link available in alert description).
2. Confirm scope: affected tenants, impacted regions, duration.
3. Identify recent deployments or configuration changes.

## Containment
- SIP/voice agent degradation: failover to human routing via Admin app, notify tenants if impact > 10 minutes.
- Order service issues: disable AI ordering in Admin app, enable manual ticketing.
- Notification service failure: switch to backup messaging channel (SMS/email).

## Communication
- Update status page every 30 minutes while incident open.
- Provide estimated time-to-resolution when known.

## Remediation Tasks
- Pull logs/metrics using shared dashboards.
- Engage SRE or vendor support for provider outages (Twilio, LiveKit, LLM vendors).
- Roll back recent releases if regression suspected.

## Resolution
- Verify metrics have returned to baseline for 30 minutes.
- Re-enable AI automations incrementally (pilot tenant first).
- Send resolution message to tenants and stakeholders.

## Post-Incident
- Create postmortem doc within 24 hours: timeline, root cause, corrective actions.
- File Jira tickets for follow-up (automation gaps, monitoring improvements, docs updates).
- Update this runbook with findings if procedure changes.

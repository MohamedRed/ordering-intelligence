# Access Onboarding & Offboarding Checklist

## Onboarding
1. **Manager request:** Submit ticket with role justification & environment scope.
2. **Identity setup:** Create Google Workspace account + enforce MFA / security key.
3. **Group membership:** Add to `engineering@`, `pagerduty-oncall@`, and least-privilege IAM groups (dev/staging/prod as required).
4. **Tooling:** Provide GitHub access, Twilio subaccount viewer, LiveKit dashboard read-only.
5. **Compliance briefing:** Share secure coding guidelines, incident response playbook, and retention policy.
6. **Secrets:** Never share raw secrets; developers must use Secret Manager or the `infra/secrets/.env` template stored in the approved secrets vault.

## Offboarding
1. **Disable Workspace account** immediately; revoke OAuth tokens.
2. **Remove group memberships** (engineering, PagerDuty, Slack).
3. **Rotate credentials** (Twilio, OpenAI, LiveKit) if the user had access.
4. **Audit access logs** for last 30 days; flag anomalies.
5. **Update IAM audit log** (`ops/security/iam/`).
6. **Collect assets** (laptops, security keys); wipe devices if corporate-managed.

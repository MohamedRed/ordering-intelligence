# Notification Channel Configuration

## Slack
1. Create a Cloud Monitoring Slack channel integration in the GCP console (Alerting → Notification channels).
2. Note the channel ID (format `projects/<project>/notificationChannels/<id>`).
3. Add the ID to `notification_channel_ids` when invoking the Terraform observability module.

## PagerDuty
1. From Cloud Monitoring, create a PagerDuty integration using your service key.
2. Copy the generated notification channel ID.
3. Pass the ID via `notification_channel_ids` or environment-specific variables.

## Email
- Supply addresses via the `alert_emails` variable in each environment; Terraform will create email channels automatically.

Update `terraform.tfvars` with:
```hcl
alert_emails = ["oncall@example.com"]
```

Existing channel IDs can be injected using locals or Terraform Cloud variables.

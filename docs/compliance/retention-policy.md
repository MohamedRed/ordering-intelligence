# Data Retention Policy

| Data Type | System of Record | Retention | Disposal Process |
| --- | --- | --- | --- |
| Raw call audio | Twilio / LiveKit (transient) | 30 days max (Twilio CDRs only) | Auto-expire in Twilio; no audio recorded by default. |
| Transcripts & dialog state | Firestore (`conversations` collections) | 90 days rolling | Nightly Cloud Task purge job (todo) deletes documents older than 90 days. |
| Orders | Firestore (`orders` collection) + BigQuery exports | 7 years (financial compliance) | Soft delete after 7 years; BigQuery tables partitioned by order date for efficient deletion. |
| Notification logs | Firestore (`notifications`), FCM | 30 days | Daily batch job truncates logs beyond retention. |
| Secrets (API keys) | Secret Manager | Active + previous version | Rotation script disables >1 version old; secrets destroyed via API. |
| Audit logs | Cloud Logging / BigQuery export | 2 years | BigQuery table TTL of 730 days; partition drop job for older data. |

Retention timers are enforced via upcoming Cloud Scheduler jobs tracked in `ops/runbooks`.

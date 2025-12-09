# Access Review Log

| Date | Reviewer | Scope | Findings | Actions |
| --- | --- | --- | --- | --- |
| 2025-10-31 | A. Ramirez (Platform Eng) | GCP dev/staging/prod projects, GitHub org, Twilio console | Removed two dormant contractor accounts from GCP; no unexpected IAM roles detected. | Disabled accounts, rotated shared Twilio API key, updated `ops/security/iam/2025-11-06-iam-audit.md`. |
| 2025-07-15 | M. Idrissi (Security) | Production-only resources (Cloud Run, Secret Manager) | Detected lingering `viewer` role on legacy Cloud Build SA. | Role removed; noted in audit file. |
| 2025-04-02 | L. Chen (Platform Eng) | GitHub teams, PagerDuty schedules | Access matched roster; no action. | — |

> Reviews are quarterly at minimum or within 30 days of personnel changes.

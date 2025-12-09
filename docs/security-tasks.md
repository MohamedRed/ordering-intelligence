# Security Tasks (Pending)

- Deploy Firestore rules (`backend/services/*/firestore.rules`) via CI.
- Enforce Secret Manager for all service credentials; remove plain env defaults in production.
- Add govulncheck (Go) and npm audit (notification-service) to CI.
- Add SAST/static lint (golangci-lint) for Go services.
- Add CSP and HTTPS/HSTS settings for web endpoints (if any web UIs served).
- IAM: least privilege service accounts for order-service, notification-service, admin-service; Pub/Sub push SA limited to subscription publish.
- Bucket security: uniform bucket-level access, CMEK if required, lifecycle TTL (see `docs/bucket-ttl.md`).
- Logging: ensure no PII in logs; mask phone/email where logged.
- Dependency update cadence: monthly check.

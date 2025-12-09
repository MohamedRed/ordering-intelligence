# Encryption & Key Management Policy

1. **At Rest**
   - Firestore, Pub/Sub, Secret Manager, BigQuery rely on Google-managed encryption by default.
   - Customer-provided encryption keys (CMEK) planned for production projects once POS integrations require it (tracked in Phase 3).
2. **In Transit**
   - All service-to-service calls use HTTPS/TLS 1.2+. Telephony media secured via SRTP between Twilio ↔ LiveKit ↔ Cloud Run.
   - Flutter apps enforce HTTPS-only endpoints (`lint-flutter-https`).
3. **Key Storage & Rotation**
   - Secrets live in Secret Manager; version labels track rotation cadence (30/90 days).
   - Automation script `npm run rotate-secrets -- --dry-run` tests rotations before production rollout.
4. **Access Controls**
   - Only dedicated runtime service accounts have `roles/secretmanager.secretAccessor`.
   - Human access requires break-glass process logged in `ops/security/iam`.
5. **Monitoring**
   - Audit logs for Secret Manager are exported to BigQuery; anomalies trigger PagerDuty (to be wired via SCC export task).

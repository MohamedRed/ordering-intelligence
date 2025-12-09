# Compliance & Data Protection (Draft)

## PII + transcripts
- Voice transcripts and audio contain PII. Store in Cloud Storage with bucket TTL (to be set via IaC) and restricted IAM.
- Firestore collections with PII: orders, deviceTokens. Apply security rules (see `backend/services/*/firestore.rules`).
- Retention target: 13 months (per product spec). Implement TTL on Storage buckets and scheduled Firestore exports for backup/retention.

## AuthZ
- Firebase ID tokens required across services; admin routes require `role=admin`; store scoping enforced in order-service via `storeIds` claim.

## Logging
- Structured logs added for notification delivery; avoid logging full payloads containing PII. Redact phone/email in logs.

## Backups
- Firestore export job (not yet scripted) to GCS; ensure exports reside in restricted bucket.

## Next actions
- Add GCS bucket TTL + uniform access via IaC.
- Add dependency scanning + IaC security checks in CI.
- Add Storage/Firestore access logs review cadence.

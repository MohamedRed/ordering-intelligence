# Compliance & Security Pass (current state)

- **Authn/Authz**: All apps use Firebase Auth. Backend services gate routes when `REQUIRE_AUTH=true`; order/admin services enforce store scoping via `storeIds` claim and `role=admin` for admin-service.
- **RBAC**: Business/admin apps rely on Firebase custom claims (`role`, `storeIds`). Ensure claims are set during onboarding; see admin-service `verifyAdmin` middleware.
- **Data residency**: Firestore/Cloud Pub/Sub in project region (set via Terraform envs). ElevenLabs/LiveKit agents: choose residency (US/EU) per vendor settings before deploy.
- **PII handling**: Orders stored in Firestore; no payment data. Logs avoid customer phone/email. Notification-service sends SMS/email via Twilio/SendGrid—API keys must be restricted.
- **Encryption**: Transport via HTTPS (Cloud Run/ALB). At rest handled by GCP defaults; add CMEK if required.
- **Retention**: Define TTLs per collection (orders, alerts, idempotency_keys). Terraform adds TTL on `expireAt` fields; services now write `expireAt` (orders via `ORDER_TTL_DAYS`, alerts 14d, idempotency keys 48h). Verify field presence before enabling TTL.
- **Secrets**: Stored in CI secrets; `.env.example` kept minimal. Never commit API keys. Rotate FCM/Twilio/SendGrid keys quarterly.
- **Vulnerability scanning**: Run `npm audit`, `cargo audit` (if present), `go test ./...` and `flutter pub outdated` in CI before releases.
- **Deployment gates**: Require Terraform plan review; block prod deploys without passing tests + smoke.

Gaps/TODO
- Add Firestore TTL policies for orders/alerts/idempotency_keys.
- Enable Binary Authorization / signed images for Cloud Run builds.
- Add periodic dependency scanning to CI (GitHub Advanced Security or `npm audit --production` and `go list -m -u all` reports).
- Document DPIA/record of processing if serving EU users.

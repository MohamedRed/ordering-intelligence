# Engineering Handbook (Security Excerpt)

## Secure Coding Guidelines
1. **Secrets:** Never commit secrets; use Secret Manager + `.env.template`.
2. **Networking:** All outbound HTTP calls must target HTTPS endpoints; Twilio/LiveKit signed requests validated server-side.
3. **Input validation:** Sanitize restaurant/customer inputs before invoking LLMs; enforce schema validation in Firestore writes.
4. **Logging:** No PII in logs. Use `order_id`/`session_id` instead of customer names/phones.
5. **Dependency hygiene:** Run `npm audit`/`flutter pub outdated` monthly; patch high CVEs immediately.

## Incident Response Contacts
- PagerDuty service: `ordering-intelligence-core`.
- Slack channel: `#infra-alerts`.

See `ops/runbooks` for full playbooks.

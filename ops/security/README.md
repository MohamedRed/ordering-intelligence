# Security Hardening Checklist

Phase 2 requires us to turn the security posture from “baseline GCP defaults”
into an auditable, policy-driven program. Use this list to track the work;
update the implementation roadmap as milestones are delivered.

## 1. IAM & Access Reviews
- [x] Inventory service accounts across dev/staging/prod and document their roles (`ops/security/iam/2025-11-06-iam-audit.md`).
- [x] Enforce least-privilege Terraform modules (dedicated Cloud Run SAs, removed project-level `roles/editor`).
- [x] Enable Cloud Audit Logs for Admin Read / Data Write categories.
- [x] Configure IAM analyzer policy guard in CI (`npm run lint-iam-bindings`).

## 2. Secrets & Key Management
- [x] Define rotation schedule for Twilio, LiveKit, OpenAI credentials (store in Secret Manager with labels).
- [x] Automate rotation via local runner (`cd ops/security && npm install && npm run rotate-secrets -- --dry-run`).
- [ ] Store shared secrets (LLM API keys) in separate projects with dedicated access groups.

## 3. Network & Endpoint Controls
- [x] Document Cloud Run ingress policies & Direct VPC egress plan (`docs/security/network-controls.md`).
- [ ] Enable Web Application Firewall (Cloud Armor) for public endpoints once traffic scales.
- [ ] Review Flutter app API calls for HTTPS-only usage and certificate pinning options (see roadmap in `docs/security/network-controls.md`).

## 4. Compliance & Data Governance
- [ ] Produce data flow diagrams for customer PII/order data.
- [ ] Establish retention policies (audio recordings, transcripts, analytics exports).
- [ ] Prepare vendor DPAs and SOC2/ISO questionnaires (Twilio, LiveKit, OpenAI, Google).

## 5. Incident Response & Monitoring
- [ ] Tie PagerDuty escalation policies to security alerts (IAM changes, audit log anomalies).
- [ ] Add Security Command Center (SCC) findings export to BigQuery for reporting.
- [ ] Draft playbooks for credential leak response and LLM misuse escalation.

## 6. Documentation & Training
- [ ] Publish secure coding guidelines in `docs/engineering-handbook.md` (create file).
- [ ] Schedule quarterly security drills (tabletop exercises) with Ops & Engineering.
- [ ] Add onboarding checklist for granting/removing developer access.

### Deliverable Tracking
- Owners: Platform Engineering + Security liaison.
- Target: Close all “High” priority items before Phase 2 exit.
- Reporting: Summaries in bi-weekly ops review; update roadmap checkboxes when sections reach ≥80% completion.

# Compliance Documentation Package

This directory tracks the artefacts required for security/compliance reviews.
Populate it as part of Phase 2 security hardening.

## Vendor Due Diligence
- [x] Twilio DPA & SOC 2 summary (`vendor-packages/twilio/README.md`)
- [x] LiveKit security whitepaper notes (`vendor-packages/livekit/README.md`)
- [x] Google Cloud CAIQ / shared responsibility matrix (`vendor-packages/google-cloud/README.md`)
- [x] OpenAI enterprise agreement & data retention policy (`vendor-packages/openai/README.md`)
- [ ] SendGrid (email) DPA – pending procurement (`vendor-packages/sendgrid/README.md`)

## Data Governance
- [x] Data flow diagrams (see `docs/compliance/data-flows.md`)
- [x] Data retention matrix (see `docs/compliance/retention-policy.md`)
- [x] Access review log (see `docs/compliance/access-review-log.md`)
- [x] Incident response postmortem template (`ops/runbooks/postmortem-template.md`)

## Policies & Procedures
- [x] Secure coding guidelines (`docs/engineering-handbook.md`)
- [x] Onboarding/offboarding checklist (`docs/compliance/onboarding-offboarding-checklist.md`)
- [x] Encryption & key management policy (`docs/compliance/encryption-key-policy.md`)
- [x] Vendor onboarding checklist (`docs/compliance/vendor-onboarding-checklist.md`)

## Audit Trails
- Store SOC / ISO certificates in `docs/compliance/vendor-packages/<vendor>/`.
- Store signed agreements in the secure document repository (link only, not checked into git).
- Update `docs/implementation-roadmap.md` once each section reaches acceptable coverage.

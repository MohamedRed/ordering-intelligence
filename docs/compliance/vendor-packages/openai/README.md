# OpenAI Vendor Package

- **Services used:** GPT-4o API for conversation orchestration, Moderation API for guardrails.
- **Data processed:** Order intents, dialog context, anonymized customer preferences (no raw payment data).
- **Security artefacts:**
  - Enterprise Agreement + DPA (signed 2025-02-03) – `vault://compliance/openai/enterprise-agreement.pdf`.
  - Data retention policy confirmation (30-day logging, opt-out enabled).
- **Controls:**
  - API keys stored in Secret Manager; rotated monthly via `ops/security` tooling.
  - Prompt library strips PII before sending to OpenAI (see backend orchestrator README).
- **Open items:** integrate OpenAI usage metrics into cost dashboard and confirm EU data processing location once available.

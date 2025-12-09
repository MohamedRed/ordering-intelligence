# Implementation Roadmap

This checklist translates the specification into actionable engineering milestones. Use it to plan sprints and track progress.

## Phase 0 – Foundations
- [x] Finalize provider selections (ASR/TTS/LLM) and procurement.
- [x] Populate Terraform modules with networking, Firestore, Pub/Sub, Secret Manager, and Artifact Registry resources.
- [x] Configure CI/CD pipelines (GitHub Actions / Cloud Build) for backend services and Flutter apps.
- [x] Implement shared configuration library for environment management across services.
- [x] Wire docker-compose stack to enable local end-to-end smoke tests.
- [x] Author bootstrap script for local toolchain (Node.js, Flutter, Python 3.11).

## Phase 1 – MVP Delivery (Revised)
- [x] Voice agents (primary): ElevenLabs hosted agents deployed via console; testing and transcript review enabled.
- [ ] Voice agents (alt): LiveKit hosted agents retained for future cost/control (not active in prod).
- [ ] Telephony adapter/orchestrator/speech pipeline (legacy) — superseded by hosted agents (no action).
- [ ] Order service: extend schema (status transitions, pricing), enable Pub/Sub-driven notifications.
- [ ] Notification service: wire to order events; add delivery/error tracking.
- [ ] Admin service: add audit logging, feature flags, RBAC.
- [ ] Business app: replace mock inbox with live orders; menu editor + push notifications.
- [ ] Admin app: tenant wizard, analytics (Looker/BigQuery) integration, live alert feed.

## Phase 2 – Operational Hardening
- [x] Observability: structured logging, OpenTelemetry tracing, Cloud Monitoring dashboards.
- [x] Incident response tooling and runbooks in `ops/`.
- [x] Automated testing: unit, integration, synthetic call flows.
- [ ] Security hardening: IAM reviews, secret rotation, compliance documentation.
- [x] Manual POS export APIs and integration scaffolding.

## LiveKit SIP Migration (Parked / Alternate Path)
- **Goal:** Enable LiveKit SIP trunks + hosted agents as a cost/control option once production confidence is high.
- **Status:** Parked. Current production path uses ElevenLabs hosted agents; keep LK configs and runbooks ready but do not cut over.

### Trunk & Agent Setup
- [ ] Author detailed architecture delta (current adapter vs LiveKit SIP) and circulate with telephony/infra stakeholders.
- [ ] Create LiveKit inbound trunk per environment using `lk sip inbound create` (numbers, `krispEnabled`, optional `allowedAddresses`), document IDs in `infra/secrets/.env`.
- [ ] Define dispatch rules (`dispatchRuleIndividual` with `call-` prefix + metadata) and pins where required; map X- headers to participant attributes for routing.
- [ ] Configure Twilio Elastic SIP trunk origination to point at `{sip_subdomain}.us.sip.livekit.cloud` (or region-specific endpoint) via Terraform-managed `<Dial><Sip>` TwiML / connection policy.
- [ ] Stand up LiveKit Voice AI agent configs (LLM, STT, TTS, VAD, `agent_name`) and check them into `docs/ai-ordering-platform-spec.md` + per-env config.
- [x] Retire legacy Cloud Run telephony service and associated analytics paths once SIP cutover is complete.

### Rollout & Testing
1. **Dev**
   - Wire Twilio test DID to new LiveKit trunk; run synthetic SIPp scenarios and `lk sip participant create` smoke tests.
   - Validate agent instructions, SIP headers-to-attributes mapping, and dispatch metadata reaching tool endpoints (order service, notification service).
2. **Staging**
   - Repeat trunk + dispatch setup with production-like Twilio creds.
   - Execute load tests (parallel synthetic calls), failover drills, and regression suite updates (integration + e2e).
   - Enable secure trunking (TLS/SRTP) and region pinning as required.
3. **Prod**
   - Cut over pilot restaurant numbers gradually while monitoring LiveKit SIP and agent metrics.
   - Update runbooks, alerting, and incident workflows to reference LiveKit SIP/Agents.

### Exit Criteria
- [ ] End-to-end calls (Dev/Staging/Prod) originate via LiveKit SIP, meeting latency + quality benchmarks.
- [ ] Synthetic regression pack exercises SIP trunks nightly.
- [x] Legacy telephony adapter, conversation orchestrator, and speech pipeline decommissioned (code + infrastructure removed).

## Phase 3 – Expansion
- [ ] POS connectors for priority systems.
- [ ] Multilingual support roadmap.
- [ ] Additional channels (web chat, messaging) leveraging conversation engine.
- [ ] Enhanced analytics and forecasting capabilities.
- [ ] GTM collateral, onboarding playbooks, and partner integrations.

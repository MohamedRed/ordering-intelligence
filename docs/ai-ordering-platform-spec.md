# AI Ordering Platform – Product & Technical Specification

**Status:** Draft v0.2  
**Last Updated:** 2025-12-07  
**Authors:** Ordering Intelligence Team  
**Audience:** Product, Engineering, Ops, Compliance

---

## 1. Vision & Strategy

- **Vision:** Empower small and medium businesses to automate and augment order taking through conversational AI, starting with restaurants and expanding to adjacent verticals.
- **Mission:** Deliver a dependable, voice-first ordering assistant that integrates with existing workflows, reduces staff overhead, and preserves control over customer experience.
- **Strategic Pillars:** 
  - Voice-first excellence with rapid call resolution.
  - Modular architecture ready for vertical-specific adaptations.
  - Enterprise-grade governance, observability, and compliance from day one.
  - Progressive integration path from hosted agents today (ElevenLabs) to deeper control and cost efficiency via LiveKit hosted agents later.

### 1.1 Objectives

- Launch MVP with a pilot restaurant, validating AI-driven call handling and order capturing.
- Provide a Flutter-based business app for real-time order intake, menu management, and alerts.
- Deliver an operator/admin Flutter app with tenant management, analytics, and deployment controls.
- Establish a GCP- and Firebase-backed platform with strong security and operational practices.
- Instrument the system for continuous learning, analytics, and rapid iteration.

### 1.2 Success Metrics (MVP)

- ≥ 85% of inbound calls fully handled by AI without human escalation.
- ≤ 90 seconds average call duration for simple orders.
- ≥ 95% order accuracy (items, modifiers, pricing).
- ≤ 5 seconds median response latency between customer utterance and AI reply.
- Operator dashboard uptime ≥ 99.5% during business hours.

---

## 2. Scope

- Voice-based ordering via Twilio DID numbers terminated primarily into ElevenLabs Voice Agents (hosted). LiveKit hosted agents remain a secondary path for cost/control and are kept in the codebase but not used in current production.
- Conversational AI orchestration leveraging hosted agent capabilities (ASR/LLM/TTS/VAD, guardrails) with platform tool calls for menus/orders/notifications.
- GCP infrastructure: Cloud Run/GKE microservices, Firestore data persistence, Cloud Storage for media, BigQuery analytics.
- Firebase services: Authentication, Cloud Functions, Cloud Messaging (push notifications), Firestore SDK for Flutter clients.
- Flutter business app (iOS/Android/Web) for staff order management and menu updates.
- Flutter operator/admin app for tenant provisioning, analytics snapshots, and alert handling.
- Order management workflows: intake, confirmation, cancellation, manual override, and status updates.
- Configurable menu/catalog management with availability and pricing controls.
- Data pipeline for logging, monitoring, and analytics (Cloud Logging, Pub/Sub, BigQuery, Looker Studio).
- Enterprise-grade security baselines: IAM, audit logging, secret management, encryption, consent recording.

### 2.2 Out of Scope (Phase 1)

- Direct POS integrations (deferred until Phase 2 after MVP validation).
- Non-voice channels such as SMS, chat, or web ordering.
- Payments processing, delivery logistics, or driver routing.
- Custom edge hardware (kiosks, tablets) beyond BYOD devices.
- On-premise deployments (cloud-only).

### 2.3 Future Considerations

- POS connectors through modular integration framework.
- Additional channels (web chat, messaging apps).
- Vertical-specific features (florists, retail, auto services).
- Advanced analytics, forecasting, and staff scheduling insights.
- Web-based admin console leveraging same backend APIs.

---

## 3. Stakeholders & Personas

| Persona | Goals | Pain Points | Primary Interfaces |
| --- | --- | --- | --- |
| **Restaurant Staff** | View/manage incoming orders, adjust availability, escalate calls | Phone interruptions, menu changes, limited staff | Business Flutter App |
| **Business Owner/Manager** | Monitor performance, update menus/pricing, manage hours | Multi-channel orders, inconsistent reporting | Business Flutter App, Reports |
| **Platform Operator** | Onboard tenants, ensure service reliability, respond to incidents | Lack of visibility, manual deployments | Admin Flutter App, Observability Tools |
| **End Customer (Caller)** | Place orders quickly, confirm details, feel confident | Long wait times, misheard orders | Voice Call |
| **Integrations Engineer (Future)** | Build POS connectors, maintain data consistency | Fragmented POS APIs, testing complexity | Integration Layer APIs |

---

## 4. Use Cases & User Journeys

### 4.1 Core Call Flow (Happy Path)
1. Customer dials restaurant number (Twilio DID) during open hours.
2. **Primary (current prod)**: Twilio webhook terminates into ElevenLabs hosted Voice Agent, which performs ASR/LLM/TTS/VAD. Agent tools invoke platform APIs (menus/orders/notifications).
3. **Alternate (standby)**: Twilio Elastic SIP trunk (via `<Dial><Sip>`) hands the call to LiveKit SIP inbound trunk, dispatching to a LiveKit Voice Agent room (kept for cost/control fallback).
4. Agent confirms items, quantities, modifiers; calculates total price and ETA.
5. Order recorded in Firestore; push notification sent to Business app; SMS/email confirmation triggered.
6. Metrics and call artifacts logged to Cloud Storage, BigQuery, and monitoring dashboards.

### 4.2 Human Handoff
- Triggered by low ASR confidence, customer request, unsupported item, or repeated errors.
- LiveKit session bridges to on-call staff device; AI mutes and introduces human agent.
- Transcript and partial order details displayed in Business app for continuity.
- Post-call, staff annotates resolution; data logged for model improvement.

### 4.3 Menu Update Workflow
- Staff logs into Business app with Firebase Auth.
- Updates item availability, price, or modifiers.
- Changes validated by backend and versioned in Firestore.
- Real-time propagation to call prompts via caching layer; updates flagged in admin dashboard.

### 4.4 Incident Response
- Monitoring detects error threshold breach (e.g., Twilio SIP trunk or LiveKit SIP failures).
- Alert sent via Firebase push, email, and Slack integration to operators.
- Admin app provides runbook, logs, and ability to reroute calls or disable AI temporarily.

---

## 5. System Architecture

### 5.1 High-Level Diagram (Textual)
```
Caller -> Twilio DID -> Twilio Elastic SIP Trunk -> **Primary:** ElevenLabs Agent (ASR/LLM/TTS/VAD) -> Tool Calls (HTTP) -> Order Service/Notification Service/Firestore
                                                   **Alternate/Future:** LiveKit SIP + Hosted Agent -> Tool Calls (HTTP)
                                                   -> Analytics Pipeline -> Pub/Sub -> BigQuery/Looker
Admin/Business Apps -> Firebase Auth -> API Gateway -> Microservices (Cloud Run/GKE) -> Firestore/Storage
```

### 5.2 Core Services

| Service | Responsibility | Tech Stack | Deployment |
| --- | --- | --- | --- |
| **Voice Agent (Primary: ElevenLabs)** | Hosted agent with ASR/LLM/TTS/VAD, prompt management, session review tooling; invokes platform HTTP tools | ElevenLabs Console + JSON configs | ElevenLabs Cloud |
| **Voice Agent (Alt: LiveKit Hosted)** | Optional path for lower cost / deeper control; SIP trunks + hosted agent presets; maintained but not active in prod | LiveKit Cloud + voice-agent-worker | LiveKit Cloud |
| **Order Service** | Menu catalog, inventory status, pricing, persistence | Go or Node.js | Cloud Run |
| **Notification Service** | FCM push, Twilio SMS, email (SendGrid) | Node.js | Cloud Functions |
| **Admin Service** | Tenant provisioning, RBAC, audit logging | Go | Cloud Run |
| **Integration Gateway (Future)** | POS connectors, webhooks, exports | TBD | Cloud Run |

### 5.3 Data Stores

- **Firestore:** Menus, orders, store configs, user profiles, call outcomes.
- **Cloud Storage:** Audio recordings, synthesized speech artifacts, compliance documents.
- **BigQuery:** Analytical datasets (orders, call metrics, usage trends) stored in dataset `ordering_analytics` (per-project).
- **Secret Manager:** Twilio, LiveKit, LLM, and other credentials.
- **Artifact Registry:** Container images for microservices.

### 5.4 Infrastructure Management

- Use Terraform for GCP resource provisioning (projects, IAM, VPC, Cloud Run services, Firestore, BigQuery datasets).
- Enforce environment separation (dev/staging/prod) with distinct projects and service accounts.
- CI/CD via Cloud Build or GitHub Actions deploying to Artifact Registry and Cloud Run/GKE.

### 5.5 LiveKit SIP Migration Plan

- **Objective:** Operate exclusively on LiveKit-managed SIP trunks and Voice AI agents (legacy Cloud Run telephony adapter retired).
- **Key Tasks:**
  - Provision LiveKit inbound trunks per environment via `lk sip inbound create`, enabling `krispEnabled`, `allowedAddresses`, and region pinning where required; record trunk IDs in Terraform-managed `infra/secrets/.env`.
  - Define dispatch rules (unique pins, room prefixes, metadata) and SIP header mappings so caller context arrives as participant attributes.
  - Configure Twilio Elastic SIP trunk origination policies or `<Dial><Sip>` TwiML to point at `{sip_subdomain}.{region}.sip.livekit.cloud`, with TLS/SRTP secure trunking.
  - Create Voice AI agent presets (LLM, STT, TTS, VAD, `agent_name`, tools) and source control their config for each environment.
  - Update infrastructure docs/runbooks describing how Terraform, secrets, and LiveKit Cloud settings are coordinated.
  - Archive remaining artifacts from the legacy telephony adapter path; rely solely on LiveKit metrics/webhooks.
- **Environment Rollout:** Dev (Twilio test DID, internal numbers) → Staging (production-like routing, synthetic load tests) → Prod (dual-run for 1 week before full cutover). Each stage requires updated regression suites, SIPp automation, and manual spot checks.
- **Testing Strategy:** Synthetic call packs invoking DTMF, transfers, failure cases; nightly `lk sip participant create` health checks; SIPp load tests; LiveKit agent unit tests covering prompt + tool updates.
- **Dependencies & Risks:** Availability of SIP admin credentials, Twilio auth + DID inventory, LiveKit agent tooling parity with orchestrator requirements, Terraform automation for secrets. Mitigate by documenting credential custodians, enabling feature flags for fast rollback, and maintaining the current adapter until KPIs are met.

---

## 6. Conversational AI Pipeline

- **Automatic Speech Recognition (ASR):** ElevenLabs (primary). LiveKit path uses LiveKit Inference with configurable vendors when enabled.
- **Language Understanding:** ElevenLabs hosted LLM (primary). LiveKit path can target OpenAI/Vertex/Anthropic via worker presets.
- **Dialog Policy:** Prompt-level guardrails within ElevenLabs; platform-side validation via tools. LiveKit path uses worker tools + prompt rules.
- **Natural Language Generation / TTS:** ElevenLabs voices. LiveKit path uses TTS configured in the agent preset.
- **Safety & Guardrails:** 
  - Prompt shields to prevent unsupported actions.
  - Confidence scoring combining ASR probability, entity resolution, and policy checks.
  - Automatic human escalation on repeated misunderstanding.
- **Voice Agent Presets:** Centralized in `infra/voice-agents/*.json` with LiveKit presets per environment; location-aware overrides (Paris, Marseille, Québec, etc.) are applied at runtime based on `stores.voice_profile.location_code`. Details live in `docs/voice-agent-presets.md`.

### 6.4 Provider Summary

The authoritative vendor matrix lives in `docs/provider-selection.md`. Current production choices:

- Telephony: Twilio Elastic SIP trunking for DID inventory.
- Voice agents: ElevenLabs hosted agents (primary). LiveKit hosted agents retained as alternate path (disabled in prod).
- ASR/TTS/LLM: ElevenLabs stack for hosted agents. LiveKit path can target OpenAI/Vertex/Anthropic + TTS of choice.
- Notifications: Firebase Cloud Messaging (push), Twilio SMS, SendGrid (Phase 2).

All procurement status, DPAs, and cost guardrails are tracked alongside the roadmap and will be reviewed quarterly.

### 6.2 Call Session Lifecycle

- Session initiated with unique `call_session_id` propagated across services.
- Audio and transcript appended to Cloud Storage and Firestore with retention policy.
- Real-time events emitted to Pub/Sub for metrics and UI updates.
- Session termination triggers summary generation (order, anomalies) and cleanup.

### 6.3 Prompt & Knowledge Management

- Store prompt templates in Firestore/Cloud Storage with versioning.
- Per-tenant prompt overrides for tone, upsell strategies, and brand messaging.
- Menu and policy context cached in Redis-compatible store (e.g., Memorystore) for low-latency retrieval.
- Provide tooling for prompt A/B testing and rollback.

---

## 7. Application Experiences

### 7.1 Business Flutter App

- **Platforms:** iOS, Android, Web (PWA).
- **Key Features:**
  - Real-time order inbox with status updates and customer contact info.
  - Manual order entry and editing.
  - Menu management (items, categories, modifiers, availability, pricing).
  - Schedule management (open/close, holiday hours).
  - Push notifications for new orders, escalations, and incidents.
  - Offline-first caching with Firestore local persistence.
  - Role-based access (manager vs staff).

### 7.2 Admin Flutter App

- **Platforms:** iOS, Android, Desktop (Flutter multi-platform).
- **Key Features:**
  - Tenant onboarding wizard (business profile, phone numbers, menu import).
  - Deployment controls (enable/disable AI, roll out updates, feature flags).
  - System health dashboards (call stats, error rates, latency).
  - Audit trails for configuration changes and staff actions.
  - Incident management (acknowledge alerts, escalate, annotate).
  - Push notifications for SLA breaches, data anomalies, or manual overrides.

### 7.3 Future Web Experience (Optional Phase 2)

- Shared backend APIs allow building a web console using Flutter Web or React.
- Could provide enhanced analytics, data exports, and management at scale.

---

## 8. Data Model Overview

### 8.1 Key Firestore Collections

| Collection | Example Fields | Notes |
| --- | --- | --- |
| `tenants` | `name`, `status`, `plan`, `contact`, `settings` | Root-level multi-tenant metadata. |
| `stores` | `tenant_id`, `timezone`, `phone_number`, `hours`, `pos_settings` | Linked to telephony configuration. |
|  | `voice_profile`: `{ location_code, preset_id }` | Determines which LiveKit preset and accent overrides to apply. |
| `menus` | `store_id`, `version`, `categories`, `items`, `modifiers`, `pricing_rules` | Versioned; supports scheduled updates. |
| `orders` | `store_id`, `call_session_id`, `items`, `totals`, `status`, `source`, `created_at` | Structured order payloads. |
| `call_sessions` | `store_id`, `transcript_uri`, `recording_uri`, `confidence`, `handoff_reason` | Tracks call outcomes and artifacts. |
| `users` | `email`, `roles`, `stores`, `permissions`, `devices` | Firebase Auth UID references. |
| `alerts` | `type`, `severity`, `message`, `status`, `acknowledged_by` | Powers operator workflows. |

### 8.2 BigQuery Schemas (Analytical)

- `orders_fact`: order_id, tenant_id, timestamp, revenue, duration, ai_handled_flag.
- `call_metrics`: call_session_id, asr_latency, tts_latency, confidence_scores, escalations.
- `menu_items_dim`: menu_item_id, category, price, popularity metrics.
- `tenant_usage`: active_users, call_volume, SLA compliance stats.

### 8.3 Data Retention & Privacy

- Order and call data retained for 13 months by default (configurable per tenant).
- Audio recordings stored encrypted; optional auto-deletion after 30/60 days.
- PII masking applied before logs reach analytics sinks; transcripts redacted for sensitive fields.

---

## 9. Integrations Strategy

### 9.1 MVP Approach

- Focus on hosted ordering: Business app acts as source of truth.
- Provide export capabilities (CSV, email summaries, basic REST API) for manual POS entry.
- Allow staff to mark orders as “sent to POS” for tracking.

### 9.2 POS Integration Framework (Phase 2+)

- Build connector SDK with standard interfaces (order create/update, menu sync, inventory updates).
- Support webhook ingestion from POS for item availability and price changes.
- Maintain integration catalog with certification status and test suites.
- Offer low-code integrations via iPaaS or RPA (e.g., UiPath) for hard-to-integrate POS systems.

---

## 10. Security, Compliance, & Privacy

- **Identity & Access:** Firebase Auth for users; GCP IAM for services; enforce MFA for admin roles; least-privilege roles with service account separation.
- **Network Security:** VPC Service Controls around Firestore/Storage; Cloud Armor for inbound HTTP endpoints; secrets isolated in Secret Manager with rotation policies.
- **Data Protection:** Encryption at rest (Cloud KMS-managed keys) and in transit (TLS 1.2+). Consent prompts for call recording. Support data subject requests (export/delete).
- **Auditability:** Cloud Audit Logs for GCP resources; custom audit events for critical application actions stored in BigQuery and exportable to SIEM.
- **Compliance Roadmap:** Align with GDPR/CCPA for data handling; evaluate PCI DSS scope once payments enter roadmap; maintain incident response plan with tabletop exercises.
- **Operational Safeguards:** Role-based approvals for configuration changes, immutability for production logs, monthly security reviews, vulnerability scanning in CI/CD.

---

## 11. Observability & Reliability

- **Logging:** Structured logs with `tenant_id`, `call_session_id`, `order_id`. Ingest to Cloud Logging; route critical events to Pub/Sub for real-time processing.
- **Metrics:** Cloud Monitoring dashboards for availability, latency, ASR accuracy, TTS latency, call completion rate, escalation rate, order accuracy.
- **Tracing:** OpenTelemetry instrumentation across services routed to Cloud Trace.
- **Alerting:** Threshold and anomaly-based alerts to PagerDuty/Slack/email; configurable per tenant for business-impacting events.
- **Resilience:** Multi-zone deployment for Cloud Run/GKE; Twilio SIP connection policies with redundant regions; LiveKit SIP region pinning + autoscaling; health checks and circuit breakers between services.
- **Disaster Recovery:** Automated backups of Firestore (daily) and BigQuery (time travel). Documented RPO/RTO targets (4 hours / 1 hour). Run failover drills quarterly.

---

## 12. DevOps & Workflow

- **Environment Strategy:** dev, staging, prod with isolated GCP projects and Firebase instances. Feature flags to control rollout.
- **Source Control:** Git (GitHub/GitLab). Trunk-based development with short-lived branches.
- **CI/CD:** Static analysis, unit tests, integration tests in CI. Automated deploy to dev; gated approval for staging/prod. Use IaC (Terraform) applied via CI.
- **Testing:** 
  - Unit tests for microservices and Flutter apps.
  - Integration tests simulating SIP call flows (Twilio test credentials + LiveKit trunks).
  - Load testing for telephony pipeline (e.g., SIPp, custom scripts).
  - End-to-end “synthetic calls” to validate live pipelines.
- **Release Management:** Semantic versioning for services and apps. Release notes tracked in admin console with rollback capability.

---

## 13. Roadmap

### Phase 0 – Foundations (Weeks 0-4)
- Finalize requirements with pilot restaurant.
- Provision GCP projects, Terraform baseline, CI/CD pipelines.
- Set up Twilio numbers + Elastic SIP trunk prerequisites, LiveKit SIP project/agents, Firebase org structure.
- Define menu schema, data contracts, and conversation prompts.
- Build mock call simulator for early testing.

### Phase 1 – MVP Delivery (Weeks 5-12)
- Stand up LiveKit SIP trunks + Voice Agent configs, implement order service, and wire notification flows.
- Develop Business Flutter app (order inbox, menu editing, alerts).
- Build lightweight Admin Flutter app (tenant setup, health dashboard).
- Integrate logging, monitoring, and alerting; run security baseline checks.
- Conduct closed beta with pilot restaurant; iterate on prompts and UX.

### Phase 2 – Operational Hardening (Weeks 13-20)
- Expand analytics (BigQuery dashboards, Looker Studio).
- Implement incident response tooling, audit trails, configurable retention policies.
- Add automated regression tests and synthetic monitoring.
- Introduce manual POS export APIs and basic integration framework scaffolding.

### Phase 2a – LiveKit SIP + Voice Agent Cutover (Weeks 18-22)
- Create LiveKit inbound trunks, dispatch rules, and Voice Agent presets per environment; document IDs/secrets in Terraform-managed `infra/secrets/.env`.
- Configure Twilio Elastic SIP origination via `<Dial><Sip>` policies targeting `{sip_subdomain}.{region}.sip.livekit.cloud`, with TLS/SRTP + region pinning where required.
- Sequential rollout:
  1. **Dev:** Twilio test DID ↔ LiveKit trunk, validate SIP header mappings + agent prompts, run SIPp + `lk sip participant create` smoke tests.
  2. **Staging:** Mirror production numbers, execute load/failover drills, integrate synthetic regression pack, verify observability + alerting.
  3. **Prod:** Gradual cutover of production numbers with enhanced monitoring (latency, ASR accuracy, call success); reroute temporarily to staffed line if KPIs regress.
- Update runbooks, Terraform modules, and QA plans to reflect SIP ownership (no webhook streaming service).

### Phase 3 – Expansion (Weeks 21-32)
- Prioritize and implement first POS connectors.
- Add multilingual support and accent handling.
- Launch enhanced admin controls (feature flags, deployment orchestration).
- Explore additional channels (web chat) leveraging existing conversation engine.
- Prepare go-to-market materials, compliance documentation, and onboarding playbooks.

---

## 14. Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| ASR/LLM accuracy insufficient | Order errors, customer dissatisfaction | Multi-engine evaluation, prompt tuning, human fallback, continuous QA |
| Menu/price drift between systems | Incorrect orders | Real-time sync, staff alerts for discrepancies, scheduled reconciliation reports |
| Twilio/LiveKit outages | Call failures | Multi-region setup, failover numbers, status page monitoring, rapid reroute to human |
| LiveKit SIP misconfiguration | Dropped/failed calls during cutover | Dev→staging→prod rollout, automated SIPp smoke tests, maintain rollback plan to staffed line while KPIs stabilize |
| Regulatory non-compliance | Legal exposure | Legal review, consent management, data retention configuration, documentation |
| Scaling costs | Unsustainable margins | Usage monitoring, autoscaling controls, negotiate provider pricing, optimize prompts |
| POS integration complexity | Delayed expansion | Modular connector framework, prioritize high-demand POS, maintain manual workflows |

---

## 15. Open Questions

- Which LLM provider offers best balance of latency, cost, and control for MVP?
- What languages and dialects are mandatory for pilot launch?
- Which POS systems do target customers currently use (for roadmap prioritization)?
- What SLA commitments are required for pilot vs. GA?
- How many human QA/operations staff need to monitor calls during beta?
- Are there regional compliance requirements (GDPR, HIPAA, PCI) for target markets?

---

## 16. Glossary

- **ASR:** Automatic Speech Recognition.
- **LLM:** Large Language Model used for conversational understanding and generation.
- **LiveKit:** Real-time audio/video infrastructure powering low-latency voice sessions.
- **Twilio DID:** Direct inward dialing number hosted by Twilio.
- **FCM:** Firebase Cloud Messaging.
- **SLA:** Service Level Agreement.
- **IaC:** Infrastructure as Code.
- **POS:** Point of Sale system used by businesses to manage orders and payments.

---

## 17. Appendices

### 17.1 External Dependencies

- Twilio Voice & Messaging APIs.
- LiveKit Cloud or self-hosted deployment.
- Speech-to-text and text-to-speech providers (Google Cloud Speech, Google TTS/ElevenLabs).
- LLM provider (OpenAI, Anthropic, Google Vertex AI – TBD).
- SendGrid or comparable email service for order summaries.
- Flutter ecosystem packages (Firebase SDK, Riverpod/Bloc, Retrofit, etc.).

### 17.2 Runbooks (To Be Authored)

- AI Conversation Quality Review Checklist.
- Incident Response: Telephony Outage.
- Incident Response: High Error Rate in Conversation Engine.
- Security Event Handling: Suspected Data Breach.
- Deployment Checklist for Flutter Apps and Backend Services.

### 17.3 Future Enhancements

- Customer-facing order status tracking via SMS/Web.
- Loyalty integrations and personalized upsell recommendations.
- In-app payment acceptance and deposit handling.
- AI-assisted staff training and knowledge base.
- Multi-tenant white-labeling for partner agencies.

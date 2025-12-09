# Provider Selection & Procurement Status

This document captures our baseline vendor choices for the AI Ordering
Intelligence platform. It is intended to unblock procurement, contract review,
and future risk assessments. Update it whenever the sourcing strategy changes.

## Voice & Real-Time Infrastructure

| Capability | Provider | Status | Notes |
| --- | --- | --- | --- |
| Telephony / PSTN access | **Twilio Programmable Voice** | ✅ Active | Moroccan and US numbers provisioned for dev/staging/prod. Synthetic call tests verified in dev. |
| Real-time media bridge | **LiveKit Cloud** | ✅ Active | Domain `ordering-intelligence-xjviyzqe.livekit.cloud` configured. Using LiveKit Inference APIs for speech provider abstraction. |
| Synthetic monitoring | Twilio Test Credentials | ⚠️ Pending | Automate synthetic call pipeline once CI credentials are issued. |

## Speech Stack

| Capability | Primary | Secondary / Fallback | Notes |
| --- | --- | --- | --- |
| Streaming ASR | **Google Cloud Speech-to-Text (v2)** | Deepgram Nova | Evaluate latency vs. cost during staging pilot. Whisper offline kept for analysis workflows. |
| Text-to-Speech | **Google WaveNet** | ElevenLabs | WaveNet covers baseline voice quality; ElevenLabs targeted for premium voice packs. Cache frequently used prompts. |

## Language & Reasoning

| Capability | Provider | Notes |
| --- | --- | --- |
| Conversational Reasoning LLM | **OpenAI GPT-4o** | Primary runtime model for orchestrator. Managed via shared prompt library with guardrails. |
| Safety / Guardrails | OpenAI Moderation + internal heuristics | Initial shield while we evaluate Vertex AI `text-moderation`. |
| Roadmap | Anthropic Claude 3, Vertex Gemini | Keep warm accounts for failover and targeted experimentation. |

## Notifications & Comms

| Channel | Provider | Status | Notes |
| --- | --- | --- | --- |
| Push (Business/Admin apps) | **Firebase Cloud Messaging** | ✅ Active | Already integrated with Flutter apps. |
| SMS fallback | Twilio | ✅ Active | Shared account with voice services. |
| Email | SendGrid (planned) | ⚠️ Contract | Stubbed endpoints; procurement scheduled for Phase 2. |

## Data & Observability

| Capability | Provider | Notes |
| --- | --- | --- |
| Logging & Metrics | Google Cloud Logging / Cloud Monitoring | Dashboards and alert policies provisioned via Terraform. |
| Analytics Warehouse | BigQuery | Datasets defined in Phase 2 plan; ingestion jobs pending. |
| Incident Management | PagerDuty + Slack | Dev environment routing verified. Production escalation policy TBD. |

## Open Items

1. **Contracts & Pricing**
   - Finalize committed-use or volume discounts with Google Cloud for Speech and TTS.
   - Secure enterprise agreement with OpenAI (or alternative) covering data retention terms.
   - Complete SendGrid (or equivalent) procurement for transactional email.

2. **Compliance & Security**
   - Confirm DPAs for all third-party vendors, especially telephony (Twilio) and LLM providers.
   - Review data residency obligations for international restaurants as we expand.

3. **Fallback Testing**
   - Add automated staging tests for Deepgram + ElevenLabs to ensure we can flip providers during incidents.
   - Document manual playbook for switching LLM providers (prompt compatibility matrix).

4. **Budget Tracking**
   - Add cost dashboards (BigQuery/Looker) once usage data is available.
   - Tie synthetic monitoring budget alerts to Twilio and OpenAI accounts.

## Change Control

- Owner: Platform Engineering
- Update cadence: review at the start of every quarter or when any provider agreement changes.
- Store signed contracts and security questionnaires in the shared compliance repository (`/compliance/vendor-packages` once initialized).

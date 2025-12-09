# LiveKit Vendor Package

- **Services used:** LiveKit Cloud (media relay) + LiveKit Inference for ASR/TTS provider abstraction.
- **Data processed:** Temporary WebRTC media streams, token claims (room + participant metadata), LLM inference payloads (per-session prompts).
- **Security artefacts:**
  - LiveKit Security Whitepaper (2025-03) – `vault://compliance/livekit/security-whitepaper.pdf`.
  - SOC 2 Type I letter provided, Type II pending (ETA Q2 2026).
- **Controls:**
  - JWT signing keys stored in Secret Manager (`livekit-api-key/secret`).
  - Token TTL capped at 60 seconds; tokens scoped per restaurant tenant.
- **Open items:** enable per-tenant usage export for anomaly detection (Phase 2 follow-up).

# Twilio Vendor Package

- **Services used:** Programmable Voice (SIP + PSTN), SMS fallback.
- **Data processed:** Caller phone numbers, call audio metadata, webhook payloads (order transcripts IDs only).
- **Security artefacts:**
  - SOC 2 Type II (2024) – stored in secure doc repo link `vault://compliance/twilio/soc2-2024.pdf`.
  - DPA signed 2025-01-12; includes EU SCCs and US state addenda.
- **Controls:**
  - Twilio console access restricted to `twilio-admins@orderingintelligence.com`.
  - API credentials rotated quarterly via `ops/security` automation.
- **Open items:** automate synthetic monitoring account funding alerts (see provider selection doc).

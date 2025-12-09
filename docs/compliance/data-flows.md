# Data Flow Diagrams (Textual Description)

## Voice Ordering Flow
1. Customer calls Twilio number → Twilio SIP trunk forwards media to LiveKit.
2. LiveKit hosted voice agent performs STT/LLM/TTS inside the session and calls configured tools (HTTP) to fetch menu data or persist orders.
3. Finalized order posted to Order Service → Firestore + Pub/Sub `orders-events`.
4. Notification Service pushes updates to Business/Admin Flutter apps via Firebase Cloud Messaging.

## Admin/Business App API Flow
1. Flutter app authenticates with Firebase; obtains HTTPS token.
2. App calls Order Service / Notification Service over HTTPS (future: through Cloud Armor-protected LB).
3. Responses cached locally; analytics events sent to BigQuery via Pub/Sub exporter.

## Data Stores
- **Firestore:** conversational state, orders, tenant configs.
- **BigQuery:** analytics dataset (`ordering_analytics`).
- **Secret Manager:** API keys (Twilio, LiveKit, OpenAI, SendGrid).

## External Destinations
- OpenAI GPT-4o (US region) – receives masked conversation text.
- Twilio Programmable Voice – handles PSTN connectivity; stores CDRs only.
- LiveKit Cloud – transient media relay; no long-term storage.

For a diagrammatic view, see `docs/ai-ordering-platform-spec.md` Section 9.

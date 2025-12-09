# Backend Services

The backend layer comprises modular microservices deployed on GCP (Cloud Run/GKE) to support AI-driven ordering flows. Planned services include:

| Service | Language | Purpose |
| --- | --- | --- |
| LiveKit Voice Agent (hosted) | TypeScript (Agents SDK) | SIP ingress, STT/LLM/TTS, tool execution (order persistence, notifications). |
| Order Service | Go or Node.js | Menu/catalog, order validation, persistence. |
| Notification Service | Node.js | Push notifications (FCM), SMS, email. |
| Admin Service | Go | Tenant management, RBAC, audit logging. |

Each service will live under `services/<service-name>` with language-appropriate tooling, tests, and Docker configurations. Shared packages (schemas, utilities) reside under `libs/`.

Refer to the platform specification for detailed responsibilities and integration flows.

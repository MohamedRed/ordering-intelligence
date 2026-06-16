# Notification Service

Dispatches alerts and order updates to staff across push, SMS, and email channels. The service integrates with Firebase Cloud Messaging, Twilio, and SendGrid based on configuration.

## Features

- Validates configuration via the shared config schema before start-up.
- Push notifications to device tokens or topics using Firebase Cloud Messaging.
- Optional SMS alerts through Twilio Programmable Messaging.
- Optional email notifications via SendGrid.
- `POST /handoff` helper endpoint used by the voice agent workflow to escalate AI calls.

## Running Locally

```bash
PATH="tools/node/bin:$PATH" npm install
PATH="tools/node/bin:$PATH" npm run dev
```

Populate `.env` from `.env.example`. The `FIREBASE_SERVICE_ACCOUNT` value may be a JSON string or a file path. When Twilio or SendGrid credentials are absent the corresponding channel is skipped gracefully.

`CORS_ORIGINS` must be set to explicit browser origins in staging and production. Wildcards are rejected in production-like environments.

# Admin Service

Go microservice granting platform operators access to tenant provisioning, RBAC management, deployment controls, and audit trails.

## Responsibilities

- Manage tenants, stores, and configuration lifecycles.
- Provide APIs for feature flags, rollout states, and LiveKit/Twilio resource mapping.
- Expose audit logs and compliance-related summaries.
- Secure endpoints with Firebase Authentication + custom claims.

Implemented so far:

- `GET /tenants` – List tenants recorded in Firestore.
- `POST /tenants` – Create a tenant record with status and owner information.
- `GET /tenants/{tenantId}` – Fetch tenant details.
- `GET /healthz` – Service health check.

## Local Development

```bash
go run ./cmd/admin-service
```

Environment variables:

- `PORT`
- `FIRESTORE_PROJECT_ID`
- `FIREBASE_PROJECT_ID`
- `GOOGLE_APPLICATION_CREDENTIALS`

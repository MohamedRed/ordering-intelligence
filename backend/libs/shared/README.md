# Shared Libraries

Reusable components shared across backend services.

Planned packages:

- `config/` – environment variable loading, structured configuration models.
- `events/` – Pub/Sub schema definitions and helpers.
- `models/` – Pydantic (Python) and TypeScript type definitions generated from shared schema (e.g., JSON Schema or Protocol Buffers).
- `observability/` – logging, tracing, metrics helpers.
- `prompt/` – prompt templates and version handling utilities.

Language-specific sharing:

- For TypeScript services, publish internal npm packages (workspace) once repository tooling is established.
- For Python services, package modules installable via Poetry path dependencies.
- For Go services, expose modules through replace directives referencing local paths.

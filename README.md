# Ordering Intelligence Platform

This repository houses the implementation of the Ordering Intelligence AI platform, delivering voice-first ordering automation for restaurants and adjacent verticals. The project is guided by the detailed specification in `docs/ai-ordering-platform-spec.md` and evolves through modular services, Flutter applications, and GCP-native infrastructure.

**Voice stack status:** ElevenLabs hosted agents are the primary path in production (rich console, transcripts, rapid iteration). LiveKit hosted agents and the voice-agent-worker remain in the repo as an alternate path for future control and cost efficiency; they are currently parked.

## Repository Layout (Initial)

- `docs/` – product and technical specifications, runbooks, and supplemental documentation.
- `backend/` – microservices (order service, notification service, voice agent worker, etc.).
  - `backend/services/menu-ingestion` – Cloud Run service that turns menu photos/PDFs into structured menus using Vision OCR + Vertex AI, with Firestore drafts.
- `apps/` – Flutter client applications for business staff and platform administrators.
- `infrastructure/` – Terraform and deployment assets for GCP/Firebase/Twilio/LiveKit resources.
- `ops/` – operational playbooks, monitoring configs, and incident response materials.

## Getting Started

1. Review the platform specification for context and roadmap.
2. Work through the Phase 0 tasks: provision baseline infrastructure, set up CI/CD, and implement core service scaffolds.
3. Bootstrap the local toolchain (Node.js, Flutter, Python 3.11) by running `./scripts/bootstrap-dev-env.sh` (macOS arm64). Add the printed `PATH` exports when running installs or dev servers.
4. Install dependencies for each component:
   - TypeScript services: `PATH="tools/node/bin:$PATH" npm install`
   - Python services: `PATH="tools/pyenv/bin:$PATH" poetry install`
   - Flutter apps: `PATH="tools/flutter/bin:$PATH" flutter pub get`
5. Copy the relevant `.env.example` files to `.env` and populate required secrets. Shared validation rules live in `backend/libs/shared/config/schema/schema.json` and are consumed by each service at runtime.
6. Track progress via issues/milestones aligned with the roadmap phases.

### Deployment Utilities

- `scripts/livekit-agent-apply.sh <env>` deploys or rotates the LiveKit-hosted voice-agent worker (wraps `lk agent ...`).
- `scripts/deploy-voice-agent-worker.sh <env>` syncs secrets and deploys the voice-agent worker to LiveKit Cloud via the LiveKit CLI (reads credentials from `infra/secrets/.env`).
- `infrastructure/twilio/` holds the Terraform stack for Twilio SIP trunks, connection policies, and credentials.
- `npm run --prefix tests/e2e sip:update-metadata -- --location-code fr-paris` keeps the LiveKit dispatch metadata aligned with store voice profiles.
- `npm run --prefix tests/e2e voice:set-profile -- --document-id store_123 --location-code fr-paris` patches Firestore with the same `voice_profile` payload so runtime overrides resolve correctly.

## Continuous Integration

GitHub Actions workflows provide baseline validation:

- `.github/workflows/backend-ci.yml` – builds Node.js, Python, and Go services.
- `.github/workflows/flutter-ci.yml` – runs `flutter analyze` for both client apps.
- `.github/workflows/terraform-ci.yml` – enforces `terraform fmt` and validates each environment configuration.

## Shared Configuration

All backend services read environment configuration via the shared libraries under `backend/libs/shared/config/`:

- Node.js services depend on `@ordering-intelligence/config` (file-based workspace package).
- Python services install `ordering-intelligence-config` via Poetry path dependencies.
- Go services import `github.com/ordering-intelligence/sharedconfig` with a `replace` directive.

The canonical schema is defined in `schema/schema.json`; update once when adding new variables to ensure consistency across languages.

## Testing

- Order service: `cd backend/services/order-service && go test ./...`
- Notification service: `cd backend/services/notification-service && PATH="tools/node/bin:$PATH" npm test`
- Flutter apps: `cd apps/business && PATH="tools/flutter/bin:$PATH" flutter analyze` (repeat for `apps/admin`)
- E2E synthetic call: `cd tests/e2e && PATH="tools/node/bin:$PATH" npm test -- --dry-run` (set `DRY_RUN=false` with credentials for a live call)

CI workflows exercise the same commands automatically on pull requests.

> ⚠️ The codebase is in its foundational stage; subsequent commits will flesh out services, infrastructure, and applications according to the spec.

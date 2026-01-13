# Terraform Infrastructure

Infrastructure-as-Code for the Ordering Intelligence platform built on GCP, Firebase, Twilio, and LiveKit.

## Structure

- `modules/` – reusable Terraform modules (networking, firestore, cloud-run, pubsub, etc.).
- `environments/` – environment-specific configurations (`dev`, `staging`, `prod`) composing modules with environment settings.
- `modules/observability` provisions Cloud Monitoring dashboards, alert policies, and notification channels.
- New: menu ingestion stack (bucket + Pub/Sub + Cloud Run service) is declared per environment; see the `menu_ingestion` resources in each environment file.

## Getting Started

1. Install Terraform >= 1.7.
2. Authenticate with GCP using service account credentials with appropriate IAM roles.
3. Copy `.tfvars.example` to `terraform.tfvars` within each environment and populate required values.
4. Run `terraform init && terraform plan` inside the desired environment directory (requires Terraform >= 1.7).

> **Note:** Twilio and LiveKit resources may require additional providers or manual setup; track them in this directory via external data sources or documentation.

## Validation

`terraform validate` requires an initialized working directory (modules/providers downloaded).

- Per environment:
  - `cd infrastructure/terraform/environments/dev && terraform init -backend=false && terraform validate`
- All environments (helper script):
  - `./scripts/terraform/validate.sh`

### Cloud Run Overrides

Each environment accepts an optional `cloud_run_overrides` map that lets you
tune per-service settings (scaling limits, CPU/memory, and extra environment
variables) without touching module code. See the commented examples inside each
`terraform.tfvars.example` for usage.

Run `npm run lint-cloud-run-overrides` from `ops/security` to validate that any
overrides conform to the expected schema before running `terraform plan`.

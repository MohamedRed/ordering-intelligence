# Core Module

Aggregates foundational GCP resources shared across environments, including:

- VPC networks and subnets.
- Serverless VPC access connectors.
- Firestore databases (Native mode).
- Artifact Registry repositories.
- Pub/Sub topics and subscriptions.
- Secret Manager secrets.

The module exposes outputs to wire individual services (Cloud Run, GKE) in environment compositions.

> Implementation pending; populate with Terraform resources as infrastructure details are finalized.

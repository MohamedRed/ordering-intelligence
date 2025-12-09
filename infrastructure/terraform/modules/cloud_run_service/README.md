# Cloud Run Service Module

Reusable Terraform module that provisions a Cloud Run (fully managed) service and
optionally configures scaling hints, container resources, and environment
variables. Secrets are mapped from Secret Manager by providing the secret ID;
the module mounts the latest version by default.

## Inputs

- `project_id`, `location`, `service_name`, `image` – identify which service to manage.
- `min_scale`, `max_scale`, `container_concurrency`, `timeout_seconds` – tuning knobs for autoscaling and request handling.
- `env_vars` – plain key/value environment variables.
- `secret_env_vars` – environment variables backed by Secret Manager secrets.

See `variables.tf` for the full list of supported arguments.

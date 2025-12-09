## Service Account Module

Creates a dedicated service account and assigns the requested project-level
IAM roles. Use this module for Cloud Run runtimes or background workers that
need least-privilege permissions.

### Inputs

- `project_id` – Target GCP project.
- `account_id` – Service account ID (without domain suffix).
- `display_name` – Human-readable name.
- `description` – Optional description.
- `project_roles` – List of IAM roles bound at the project level.

### Outputs

- `email` – The service account email address.

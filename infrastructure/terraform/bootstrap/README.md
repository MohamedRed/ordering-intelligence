# Bootstrap layer

Creates a new GCP project, links billing through the project resource, and enables only the minimal APIs needed for the main Terraform stack.

## Files
- `main.tf` – project creation with billing, minimal API enables.
- `variables.tf` – inputs (project_id, project_name, billing_account, org_id/folder_id, enable_apis, labels).
- `terraform.tfvars.example` – sample values to copy to `terraform.tfvars`.

## Usage
```sh
cd infrastructure/terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # edit values
terraform init
terraform apply
```

### Required IAM for the caller
- On the billing account: `roles/billing.user`
- On the org (or folder): `roles/resourcemanager.projectCreator` (and `roles/resourcemanager.folderCreator` if creating folders)

## Next step
Use the resulting `project_id` as input to `infrastructure/terraform/environments/dev` (main stack) to provision services like menu-ingestion. 

## Dev project recovery notes

The current dev replacement project ID is `ordering-intelligence-dev`. After applying this bootstrap layer and the main `environments/dev` Terraform stack, set the GitHub repository variable used by `web-integration-smoke.yml`:

```sh
gh variable set GCP_DEV_PROJECT_NUMBER --repo MohamedRed/ordering-intelligence --body "$(gcloud projects describe ordering-intelligence-dev --format='value(projectNumber)')"
```

The web integration workflow authenticates as `github-ci-dev@ordering-intelligence-dev.iam.gserviceaccount.com` through the Workload Identity Pool created by the dev Terraform stack. Until the replacement project exists and `GCP_DEV_PROJECT_NUMBER` is set, the workflow fails fast with a configuration error rather than referencing the deleted `liive-dev` project number.

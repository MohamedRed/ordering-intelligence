# Bootstrap layer

Creates a new GCP project, links billing, and enables only the minimal APIs needed for the main Terraform stack.

## Files
- `main.tf` – project creation, billing link, minimal API enables.
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

# Environment Configurations

Each environment directory (`dev`, `staging`, `prod`) composes Terraform modules with environment-specific variables.

## Usage

```bash
cd infrastructure/terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

Populate `terraform.tfvars` with the correct GCP project ID, region, and billing account (if creating new projects).

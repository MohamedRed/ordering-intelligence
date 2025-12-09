# Twilio SIP Terraform Configuration

This module provisions the Twilio pieces required for the LiveKit SIP migration:

- Inbound SIP trunk that terminates calls and forwards them to LiveKit.
- Optional outbound trunk for PSTN transfers initiated by LiveKit.
- Connection policy used by Twilio `<Dial><Sip>` applications.
- Optional credential list that LiveKit can use when registering back to Twilio.

## Prerequisites

1. Install Terraform `>= 1.5`.
2. Install the Twilio Terraform provider (`terraform init` handles this automatically).
3. Export the following environment variables (or use a Terraform Cloud workspace):

```bash
export TF_VAR_twilio_account_sid="AC..."
export TF_VAR_twilio_auth_token="your-auth-token"
```

Alternatively populate `terraform.tfvars` (do **not** commit secrets to the repo).

## Usage

```bash
cd infrastructure/twilio
cp terraform.tfvars.example terraform.tfvars   # update for your environment

terraform init
terraform plan
terraform apply
```

Key variables:

- `livekit_sip_subdomain` / `livekit_sip_region`: point Twilio at the correct LiveKit SIP endpoint.
- `termination_allowed_cidrs`: CIDR ranges allowed to originate SIP traffic (set to LiveKit’s egress IPs or your test IPs).
- `inbound_phone_numbers`: map of labels → Twilio Phone SIDs (attach DID(s) to the trunk).
- `fallback_targets`: optional SIP URIs to use if LiveKit is unavailable.
- `create_credential_list`, `sip_username`, `sip_password`: create/register SIP credentials for LiveKit.

## Outputs

Run `terraform output` after apply to capture the following values for secrets:

- `inbound_trunk_sid`
- `outbound_trunk_sid`
- `connection_policy_sid`
- `credential_list_sid`

These SIDs should be copied into `infra/secrets/.env` (and your chosen secure vault) so automation scripts and tests can reference the correct identifiers.

## Notes

- The Twilio provider currently has no notion of LiveKit projects; we simply point the Twilio SIP resources at the LiveKit SIP ingress URI.
- We do not manage LiveKit resources via Terraform because LiveKit does not yet expose a Terraform provider. Hosted agent deployment remains CLI/API driven.
- `terraform destroy` will detach phone numbers from the trunk (but will not release the numbers themselves).


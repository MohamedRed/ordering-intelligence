# Cloud Run v2 Direct VPC egress: network/subnet format mismatch

## Symptom
Terraform apply fails updating a `google_cloud_run_v2_service` with an error like:

- `Expected a network name like projects/*/global/networks/*, but obtained https://www.googleapis.com/compute/v1/projects/...`

## Cause
Cloud Run v2 `template.vpc_access.network_interfaces.network/subnetwork` expects **resource IDs** in `projects/...` form, not `self_link` URLs.

## Fix
- Use `google_compute_network.id` and `google_compute_subnetwork.id` for Cloud Run v2 direct egress.
- Keep using `self_link` for resources that require it (e.g., Memorystore `authorized_network`).

# Common Errors / Fixes (Ordering Intelligence)

This file collects “gotchas” we hit in this repo and the fixes, so we don’t waste time rediscovering them.

## Cloud Run behind Serverless HTTPS LB returns `403` for all requests

**Symptom**
- Hitting the Load Balancer hostname (e.g. `dev-agent-webhooks.<ip>.nip.io`) returns `HTTP 403` with a small HTML body for *every* path (even `/healthz`).
- Cloud Armor policy appears to be `default allow`, yet requests still fail.

**Root cause**
- The serverless HTTPS LB module (`infrastructure/terraform/modules/serverless_https_lb`) created the backend service with `protocol = "HTTPS"`.
- For Cloud Run **serverless NEGs**, the backend is reached via **HTTP**. The HTTPS protocol setting can produce opaque edge errors like blanket `403`.

**Fix**
- Set backend protocol to **HTTP** in:
  - `infrastructure/terraform/modules/serverless_https_lb/main.tf`
- Apply Terraform for the environment.

## Cloud Armor allowlist blocks local testing (always `403`)

**Symptom**
- Requests to LB hostname always return `HTTP 403` from your laptop.
- ElevenLabs calls may work (if their egress IP matches) but local curl/browser tests don’t.

**Root cause**
- Cloud Armor policy is configured as an IP **allowlist** (default deny all other IPs).

**Fix (dev)**
- Toggle allowlisting off so policy becomes **default allow + rate limit**:
  - `infrastructure/terraform/environments/dev/variables.tf`:
    - `enable_elevenlabs_ip_allowlist = false`
- Re-apply Terraform.

## Stripe webhook signature failures (`invalid_signature`)

**Symptom**
- Stripe webhook requests return `400 invalid_signature` or `missing_signature`.

**Root cause**
- Stripe requires the **raw request body** for signature validation. If the JSON body parser runs first, the payload changes and verification fails.

**Fix**
- Use `express.raw({ type: "application/json" })` for the Stripe webhook route and pass the raw buffer to `stripe.webhooks.constructEvent`.
- Ensure `STRIPE_WEBHOOK_SECRET` is set for the service handling webhooks.

## Duplicate Stripe webhook delivery (idempotency)

**Symptom**
- Multiple `checkout.session.completed` events for the same session cause duplicate status updates or submissions.

**Root cause**
- Stripe retries webhooks; delivery is **at least once**.

**Fix**
- Make webhook handlers idempotent:
  - Update payment status by `payment_id` and check group order status before re-submitting.
  - Use an idempotency key when creating the final order.


# Network & Endpoint Controls

This document captures the current ingress posture for our Cloud Run services,
plus the roadmap for hardening outbound connectivity and perimeter defenses.

## 1. Cloud Run Ingress

| Service | Environment(s) | Ingress Mode | Notes |
| --- | --- | --- | --- |
| `order-service` | dev/staging/prod | `all` (public) | Public so Flutter apps can call the API without a gateway. This will be fronted by Cloud Armor + HTTPS LB in Phase 2. |
| `admin-service` | dev/staging/prod | `all` (public) | Used by internal tooling; migrate behind the same HTTPS LB after order-service lockdown. |

### Action Items

1. **Short term (now):** keep all services on `ingress = "all"` but require IAM auth (already enabled) and rate limits via Twilio/LiveKit.
2. **Phase 2 exit:** move `order-service` and `admin-service` behind an HTTPS Load Balancer with Cloud Armor policies; LiveKit Cloud now handles voice ingress directly.
3. **Phase 3:** introduce per-tenant domains + mTLS for B2B integrations.

## 2. Direct VPC Egress Plan

Google now recommends Direct VPC egress for Cloud Run over Serverless VPC
connectors. Our rollout plan:

1. **Design (in progress):**
   - Catalog private resources (Firestore, future SQL/POS APIs) that need private RFC1918 access. Today everything is public, so no connector is required.
   - Define subnet ranges for Direct VPC egress (likely `/28` per region) and reserve them in Terraform.
2. **Implementation (Phase 2 milestone):**
   - Enable Direct VPC egress on `order-service` once we introduce private integrations (POS, analytics).
   - Update Terraform module `cloud_run_service` to accept `vpc_access` settings for Direct egress and roll it out per environment.
3. **Validation:**
   - Update synthetic tests to ensure services can still reach LiveKit/Twilio.
   - Monitor egress metrics for unexpected cost spikes.

## 3. Cloud Armor / WAF Rollout

| Milestone | Description | Owner | Target |
| --- | --- | --- | --- |
| Design | Define baseline Cloud Armor rules (rate limits, geo blocks, bot defense) for HTTPS LB fronting `order-service`. **Status:** complete – see Terraform module `modules/cloud_armor_policy`. | Platform Eng | ✅ Nov 2025 |
| Staging Pilot | HTTPS LB `staging-order-service.136-110-149-137.nip.io` + Cloud Armor deployed; waiting for managed certificate issuance before switching Flutter pins from “allow any”. Synthetic health check verified via `curl -k`. | Platform Eng | ✅ Nov 2025 |
| Production Cutover | HTTPS LB `prod-order-service.136-110-164-99.nip.io` provisioned with Cloud Armor. Certificate is provisioning; keep monitoring before pointing real traffic. | Platform Eng | ✅ Nov 2025 |
| Lockdown | Removed temporary `allUsers` bindings; Cloud Run now only trusts the project’s `service-${projectNumber}@serverless-robot-prod.iam.gserviceaccount.com` identity. Mesh dataplane API is still unavailable, so keep tracking the upgrade for when Google exposes it. | Platform Eng | ✅ Nov 2025 |

> **Mesh dataplane status:** `gcloud services enable meshdataplane.googleapis.com` still returns `SERVICE_CONFIG_NOT_FOUND_OR_PERMISSION_DENIED` for all environments (Nov 2025). Until Google enables the API for our org, we rely on the existing serverless-robot service account as the load-balancer principal. Re-run the enable + `gcloud beta services identity create --service meshdataplane.googleapis.com` flow periodically and swap the IAM binding once the managed identity becomes available.

### Managed Certificate & Pinning Workflow

1. GCP issues the managed certificate automatically (verify status with  
   `gcloud compute ssl-certificates describe <env>-order-service-managed --project <project>`).
2. Once status is `ACTIVE`, run  
   `node scripts/update-order-service-pins.mjs --env=<env>` to refresh the SHA256 pins in both Flutter apps.  
   (The script pulls `terraform output order_service_lb_hostname`, grabs the live cert, and updates `apps/*/lib/bootstrap/pins.dart`.)
3. Commit the updated fingerprints and remove the temporary blank pin entry for staging once the cert is ready.
4. After Google exposes the mesh dataplane service account, remove the `allUsers` invoker binding with  
   `gcloud run services remove-iam-policy-binding order-service --region us-central1 --project <project> --member allUsers --role roles/run.invoker`.

## 4. Flutter Client API Review

All Flutter apps currently use HTTPS endpoints. Pending tasks:

1. Enforce HTTPS-only URLs via the repo lint (`npm run lint-flutter-https`, executed in `.github/workflows/flutter-ci.yml`).
2. Admin & business apps pin the order-service load balancer certificates via `lib/bootstrap/https_pins.dart`. Use `node scripts/update-order-service-pins.mjs` to refresh pins after each cert rotation.
3. Document downgrade/SSL error handling to avoid leaking PII in error toasts.

Tracking for these tasks lives in `ops/security/README.md` under "Network & Endpoint Controls".

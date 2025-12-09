## Serverless HTTPS Load Balancer Module

Creates the minimal resources required to front a Cloud Run service with the
Global HTTPS Load Balancer:

- Serverless NEG pointing to the Cloud Run service.
- Backend service with Cloud Armor policy attachment.
- URL map, HTTPS proxy, forwarding rule, and reserved IP.
- Ephemeral self-signed certificate (for staging) exposing a configurable host
  name so that clients can pin the certificate fingerprint until a managed cert
  is available.

### Inputs
- `project_id`, `region`, `cloud_run_service`, `environment_name`
- `hostname` – CN used for the self-signed certificate.
- `security_policy_id` – Cloud Armor policy to enforce.

### Outputs
- Global IP address, hostname, and PEM certificate (for pinning / curl tests).

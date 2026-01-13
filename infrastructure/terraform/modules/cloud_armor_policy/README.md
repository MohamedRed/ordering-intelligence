## Cloud Armor Policy Module

Creates a reusable Cloud Armor security policy with optional IP blocklist and
per-IP rate limiting. Intended to be attached to HTTPS load balancers or other
supported backends as we roll out WAF protections.

### Inputs
- `project_id` – Project that owns the policy.
- `enabled` – Set to `false` to skip creating the policy (outputs will be `null`).
- `policy_name` – Unique name for the Cloud Armor policy.
- `description` – Optional description.
- `blocked_ip_ranges` – Optional list of CIDR ranges to deny.
- `allowed_ip_ranges` – Optional list of CIDR ranges to allow (enables default deny).
- `enable_rate_limit`/`rate_limit_*` – Parameters for baseline per-IP throttling.

### Outputs
- `policy_id` – Fully qualified ID of the policy.
- `policy_name` – Policy name (useful for attachments).

# Secrets Hand-off

`infra/secrets/.env` is intentionally `.gitignored`; keep the canonical copy in a secure vault (Secret Manager, Bitwarden, etc.) and sync to local machines via our onboarding checklist.

## Required Keys (LiveKit SIP Migration)

Add the following environment variables for each environment (`DEV`, `STAGING`, `PROD`). Substitute the suffix with the uppercase env name (e.g., `LIVEKIT_SIP_INBOUND_TRUNK_ID_DEV`).

| Key | Description | Example |
| --- | --- | --- |
| `LIVEKIT_SIP_INBOUND_TRUNK_ID_<ENV>` | LiveKit inbound trunk ID created via `lk sip inbound create`. | `LIVEKIT_SIP_INBOUND_TRUNK_ID_DEV=TR_abcdef123456` |
| `LIVEKIT_SIP_DISPATCH_RULE_ID_<ENV>` | Dispatch rule that hands callers into rooms. | `LIVEKIT_SIP_DISPATCH_RULE_ID_DEV=DR_0123abcd` |
| `LIVEKIT_SIP_OUTBOUND_TRUNK_ID_<ENV>` | LiveKit outbound trunk ID (`lk sip outbound create`). | `LIVEKIT_SIP_OUTBOUND_TRUNK_ID_DEV=ST_bZY9fiZv8yVe` |
| `LIVEKIT_VOICE_AGENT_ID_<ENV>` (optional) | Voice AI agent ID if external automation needs it. The canonical source lives in `backend/services/voice-agent-worker/livekit.<env>.toml`. | `LIVEKIT_VOICE_AGENT_ID_STAGING=AG_fghijk789` |
| `LIVEKIT_SIP_HEALTH_CALL_TO_<ENV>` | Phone number the SIP health check should dial. | `LIVEKIT_SIP_HEALTH_CALL_TO_DEV=+12173875350` |
| `TWILIO_SIP_TRUNK_SID_<ENV>` | Twilio Elastic SIP trunk SID tied to the DID(s). | `TWILIO_SIP_TRUNK_SID_PROD=TKxxxxxxxx` |
| `TWILIO_CONNECTION_POLICY_SID_<ENV>` | Origination connection policy SID used for `<Dial><Sip>` routing. | `TWILIO_CONNECTION_POLICY_SID_DEV=OPyyyyyyyy` |
| `TWILIO_DID_<ENV>` | Comma-separated Twilio phone numbers for the environment. | `TWILIO_DID_STAGING=+15105550100,+15105550123` |
| `TWILIO_SIP_CREDENTIAL_LIST_SID_<ENV>` | Credential list SID attached to the Elastic SIP trunk. | `TWILIO_SIP_CREDENTIAL_LIST_SID_DEV=CLxxxx` |
| `TWILIO_SIP_USERNAME_<ENV>` / `TWILIO_SIP_PASSWORD_<ENV>` | Termination credentials Twilio expects for outbound calls. | `TWILIO_SIP_USERNAME_STAGING=oi-staging-sip` |
| `LIVEKIT_SIP_REGION_<ENV>` | Region pin for inbound trunk (`us`, `eu`, `india`, etc.). | `LIVEKIT_SIP_REGION_PROD=us` |
| `LIVEKIT_SIP_ADMIN_KEY` / `LIVEKIT_SIP_ADMIN_SECRET` | Credentials with SIP admin grant (shared across envs). | Stored once; reference from CI. |
| `LIVEKIT_AGENT_API_KEY_<ENV>` (optional) | API key for LiveKit Agents if distinct per env. | `LIVEKIT_AGENT_API_KEY_DEV=sk_livekit_dev...` |

> Store Twilio auth tokens (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`) and existing service secrets alongside these entries as before. Rotate credentials when staff changes per `docs/compliance/onboarding-offboarding-checklist.md`.

## Sample `.env`

```
# Dev
TWILIO_ACCOUNT_SID=ACxxxx
TWILIO_AUTH_TOKEN=*****
TWILIO_SIP_TRUNK_SID_DEV=TKxxxx
TWILIO_SIP_CREDENTIAL_LIST_SID_DEV=CLxxxx
TWILIO_SIP_USERNAME_DEV=oi-dev-sip
TWILIO_SIP_PASSWORD_DEV=superSecret
LIVEKIT_SIP_INBOUND_TRUNK_ID_DEV=ST_xxxx
LIVEKIT_SIP_OUTBOUND_TRUNK_ID_DEV=ST_out_xxxx
LIVEKIT_SIP_DISPATCH_RULE_ID_DEV=SDR_xxxx
LIVEKIT_SIP_HEALTH_CALL_TO_DEV=+1XXXXXXXXXX
LIVEKIT_SIP_REGION_DEV=us

# Repeat for STAGING / PROD...
```

Sync updates back to your chosen vault after every trunk/dispatch/agent creation so the table in `docs/livekit-sip-migration.md` can be populated.

## GitHub Actions Secrets

The nightly LiveKit SIP health workflow (`.github/workflows/sip-health.yml`) expects the following repository secrets for each environment. Set them in GitHub with the exact names below (replace `<ENV>` with `DEV`, `STAGING`, `PROD`):

- `<ENV>_LIVEKIT_URL`
- `<ENV>_LIVEKIT_API_KEY`
- `<ENV>_LIVEKIT_API_SECRET`
- `<ENV>_LIVEKIT_SIP_INBOUND_TRUNK_ID`
- `<ENV>_LIVEKIT_SIP_DISPATCH_RULE_ID`
- `<ENV>_LIVEKIT_SIP_OUTBOUND_TRUNK_ID`
- `<ENV>_LIVEKIT_SIP_HEALTH_CALL_TO`

Optional (set only if used and ensure the workflow references them before adding):

- `<ENV>_LIVEKIT_SIP_EXPECTED_NUMBERS`
- `<ENV>_LIVEKIT_SIP_EXPECTED_PIN`
- `<ENV>_LIVEKIT_SIP_HEALTH_DTMF`

Keep GitHub secrets synchronized with `infra/secrets/.env` so local tooling and CI run against the same identifiers.

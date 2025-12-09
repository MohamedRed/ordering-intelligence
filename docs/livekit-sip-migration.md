# LiveKit SIP Migration – Architecture Delta

**Status:** Draft (2025-11-08) — Parked / standby (ElevenLabs is current production path)  
**Owners:** Telephony Platform + Infra

## 1. Purpose

Describe the concrete differences between the legacy Twilio `<Stream>` telephony adapter and the target LiveKit SIP + Voice Agent workflow so each team (telephony, infra, QA, ops) can execute the cutover without hunting through multiple docs.

## 2. Current State (Legacy)

- Twilio Programmable Voice webhooks hit the Cloud Run `telephony-adapter` service.
- Adapter validates signatures, issues LiveKit access tokens, and multiplexes media via `<Stream>` to our speech pipeline.
- Session metadata and call analytics are emitted from the adapter; Twilio remains the SIP endpoint.
- Secrets tracked: `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TELEPHONY_WEBHOOK_SECRET`, `LIVEKIT_KEY/SECRET`.

## 3. Target State (LiveKit SIP)

- Twilio Elastic SIP trunks route calls (via `<Dial><Sip>` or connection policies) directly to LiveKit SIP inbound trunks.
- LiveKit dispatch rules determine the destination LiveKit room and attach SIP attributes for routing metadata.
- Voice AI agents (LiveKit Agents) handle media, ASR/LLM/TTS, and tool calls; our Cloud Run services observe via webhooks/events only.
- Legacy Cloud Run telephony adapter has been retired; LiveKit now owns SIP ingress and media end-to-end.
- Secrets tracked: LiveKit SIP Admin Key, per-environment inbound trunk IDs, dispatch rule IDs, Voice Agent IDs, Twilio trunk SIDs, and connection policy SIDs.

## 4. Delta Summary

| Area | Legacy Implementation | LiveKit SIP Target | Required Action |
| --- | --- | --- | --- |
| Call Entry | Twilio webhooks → Cloud Run adapter → LiveKit session token | Twilio Elastic SIP trunk → `{sip_subdomain}.{region}.sip.livekit.cloud` endpoint | Create LiveKit inbound trunks + dispatch rules; update Twilio connection policies / `<Dial><Sip>` TwiML |
| Media Handling | Adapter proxies audio via `<Stream>` | LiveKit Voice Agent owns media, ASR, LLM, TTS | Configure agent presets (LLM, STT, TTS, tools) per environment |
| Credentials | `TWILIO_*`, `LIVEKIT_KEY/SECRET` stored per service | Add trunk IDs, dispatch IDs, agent IDs, Twilio SIP creds | Extend `infra/secrets/.env` template; coordinate with Secret Manager |
| Observability | Adapter metrics (`telephony_adapter_http_errors`, LiveKit token issuance failures) | LiveKit SIP metrics (dispatch matches, SIP call states), Twilio SIP trunk alarms | Migrate dashboards/alerts to LiveKit + Twilio metrics; remove Cloud Run telemetry for the adapter/orchestrator/pipeline |
| Testing | Synthetic call runner hitting webhook path | SIPp + `tests/e2e/scripts/validate_dispatch.ts` (LiveKit SIP health call) + live Twilio `<Dial><Sip>` synthetic calls | Add nightly SIP regression job + update `tests/README.md` plan |
| Runbooks | Telephony outage instructions reference adapter + LiveKit tokens | Focus on SIP trunk/dispatch troubleshooting and LiveKit Cloud diagnostics | Update `ops/runbooks/telephony-outage.md` (done in this change) |

## 5. Credential & Secret Inventory

All IDs must be tracked in `infra/secrets/.env` (encrypted at rest). Use the following keys:

- `LIVEKIT_SIP_INBOUND_TRUNK_ID_<ENV>`
- `LIVEKIT_SIP_DISPATCH_RULE_ID_<ENV>`
- `LIVEKIT_VOICE_AGENT_ID_<ENV>`
- `TWILIO_SIP_TRUNK_SID_<ENV>`
- `TWILIO_CONNECTION_POLICY_SID_<ENV>` (if applicable)
- `TWILIO_DID_<ENV>` (list or comma-separated)
- `LIVEKIT_SIP_REGION_<ENV>` (e.g., `us`, `eu`, `india`)

| Environment | Twilio DID(s) | Twilio SIP Trunk SID | Twilio Connection Policy SID / Voice App SID | LiveKit Inbound Trunk ID | LiveKit Outbound Trunk ID | Dispatch Rule ID | Voice Agent ID | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dev | `+1-217-387-5350` | `TKc658a7ed05acd9346d763f4a1236eb11` | `NY075430ce21d670b596625134df5c34d8` | `ST_uMDDc57uX8jb` | `ST_HgEigW32h4WF` | `SDR_MuDhXunexXce` | _TBD_ | Credential list `CLcde64ecc6f80ee5f5e2e580810a532b7` (`oi-dev-sip`), origination URL `OU21064336d7eab35cc54fee7167adf74c`. LiveKit trunk metadata: `environment=dev,tenantId=pilot-dev`. Config: `infra/voice-agents/dev.json`. |
| Staging | `+1-507-620-5552` | `TK90d84736c56836c3ed6d78bd4b75b3fd` | `NY8d37b6906cec6a7e9d5c880473275f25` | `ST_xDFQKT7ndYaG` | `ST_Sax6QQi2M86B` | `SDR_2BvRkV33J7aU` | _TBD_ | Credential list `CL4a0c0c26c8e55c92cf373ab0224e7193` (`oi-staging-sip`), origination URL `OU5156454234e6fffc5e355a2b94857940`. LiveKit trunk metadata: `environment=staging,tenantId=pilot-staging`. Config: `infra/voice-agents/staging.json`. |
| Prod | `+1-254-280-4953` | `TK8d9ffcd330f1e1dcb565fc2f7d0e4f37` | `NY38de4d3b2c28d2e6841ed42e15ab1583` | `ST_TT9snTcgZJVf` | `ST_Wnz3xstZLseZ` | `SDR_zv6scMco27hb` | _TBD_ | Credential list `CL2ccf0876f2b95976b8b36eb8b6b150b4` (`oi-prod-sip`), origination URL `OUfa7f3f01150c1982993c80cd1f5d7317`. LiveKit trunk metadata: `environment=prod,tenantId=pilot-prod`. Config: `infra/voice-agents/prod.json`. |

> **How to populate:** After provisioning each component, run `lk sip inbound list`, `lk sip dispatch list`, or capture IDs from the LiveKit Cloud UI. Twilio SIDs are available via `twilio api trunking v1 trunks list` and `twilio api trunking v1 origination-urls list`.

### 5.1 Provider routing (US first-party PSTN vs SIP trunk)

- **US stores:** Use LiveKit first-party phone numbers (US-only, inbound-only). Buy the number in LiveKit Cloud/CLI, attach it to the dispatch rule above, and set your runtime config to:
  - `telephony.provider = us-livekit-pstn`
  - `telephony.number = <E.164 LiveKit number>`
  - `telephony.dispatch_rule_id = <LIVEKIT_SIP_DISPATCH_RULE_ID_<ENV>>`
  Point health checks and e2e calls at this LiveKit number to prevent international dial-outs.
- **Non-US stores:** Keep the external SIP trunk (Twilio/Telnyx/Plivo) terminating the local DID into the LiveKit inbound trunk. Set `telephony.provider = sip-trunk` and continue to use the carrier DID + trunk/dispatch IDs.
- **Routing logic:** In the agent/worker, route calls based on `telephony.provider`. Do **not** forward non-US DIDs to US LiveKit numbers (that becomes international PSTN).
- **Safety rails:** Keep carrier geo-permissions enabled, set max call duration on dispatch/agent, and maintain separate health checks per provider.

## 6. Deployment & Rollout Sequence

1. **Dev**
   - Provision inbound trunk + dispatch rule + Voice Agent.
   - Point Twilio test DID to `{sip_subdomain}.us.sip.livekit.cloud` (or region needed).
   - Run SIPp scenarios and `npm run sip:validate -- --run-call` smoke tests after each change.
2. **Staging**
   - Clone production Twilio numbers into staging trunk/connection policy.
   - Enable TLS/SRTP and test region pinning by forcing `destination_country`.
   - Add staging synthetic SIP regression (hourly) hitting dispatch rule pins.
3. **Prod**
   - Populate `infra/secrets/.env` with prod IDs.
   - Confirm all Twilio origination routes to the LiveKit SIP trunk (legacy webhook path removed).
   - Archive any remaining Cloud Run adapter artifacts and monitoring rules.
   - Legacy Cloud Run telephony/speech/orchestrator services are deprecated; when the SIP cutover is stable, remove them from Terraform state and delete the services to avoid drift (ensure state backend is set before destroy).

### 6.1 Provisioning Checklist & Command Templates

0. **Provision Twilio infrastructure**
   - Recommended: run `terraform init && terraform apply` in `infrastructure/twilio/` for the target environment. This configures trunks, connection policy, credential list, and DID mappings from code.
   - The steps below are retained for reference or ad-hoc CLI usage.

1. **Create inbound trunk**
   ```bash
   cat <<'EOF' > inbound-trunk.json
     {
       "trunk": {
         "name": "oi-${ENV}-inbound",
         "numbers": ["+1XXXYYYZZZZ"],
         "allowedAddresses": ["X.X.X.X/32"],
         "headersToAttributes": {
           "X-Tenant-ID": "tenantId"
         }
       }
     }
   EOF
   lk sip inbound create inbound-trunk.json
   ```
   - Record the returned `sip_trunk_id` in `infra/secrets/.env` (`LIVEKIT_SIP_INBOUND_TRUNK_ID_<ENV>`).

2. **Create dispatch rule**
   ```bash
   cat <<'EOF' > dispatch-rule.json
   {
     "dispatchRule": {
       "name": "oi-${ENV}-call-room",
       "rule": {
         "dispatchRuleIndividual": { "roomPrefix": "call-" }
      },
      "roomConfig": {
        "agents": [
          {
            "agentName": "${VOICE_AGENT_NAME:-oi-voice-agent}"
          }
        ]
      },
       "trunkIds": ["<INBOUND_TRUNK_ID>"],
       "attributes": {
         "environment": "${ENV}",
         "tenantId": "<tenant-id>"
       }
     }
   }
   EOF
   lk sip dispatch create dispatch-rule.json
   ```
  - The `agentName` must match the value exported by the worker (default `oi-voice-agent`, override via `VOICE_AGENT_NAME`). This enables explicit dispatch and avoids LiveKit assigning calls to unintended agents.
   - Save `sip_dispatch_rule_id` into `.env` (`LIVEKIT_SIP_DISPATCH_RULE_ID_<ENV>`). If using pins, capture them for runbooks/tests.

3. **Configure Twilio Elastic SIP trunk / `<Dial><Sip>`**
   - Create/Update trunk via CLI:
     ```bash
     twilio api trunking v1 trunks update \
       --sid TKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
       --friendly-name "OI ${ENV} LiveKit" \
       --domain-name "oi-${ENV}.pstn.twilio.com"
     ```
   - Add origination URL pointing at the LiveKit region endpoint:
     ```bash
     twilio api trunking v1 trunks origination-urls create \
       --trunk-sid TKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
       --sip-url "sip:${SIP_SUBDOMAIN}.${REGION}.sip.livekit.cloud" \
       --priority 1 --weight 1 --enabled
     ```
   - Optionally create a Voice Connection Policy so Twilio `<Dial><Sip>` apps or future BYOC targets reference the same LiveKit endpoint:
     ```bash
     twilio api voice v1 connection-policies create --friendly-name oi-${ENV}-connection-policy
     twilio api voice v1 connection-policies targets create \
       --connection-policy-sid NYxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
       --target "sip:${SIP_SUBDOMAIN}.${REGION}.sip.livekit.cloud" \
       --friendly-name LiveKit-${REGION} --priority 1 --weight 1 --enabled
     ```
   - Store `TWILIO_SIP_TRUNK_SID_<ENV>` and `TWILIO_CONNECTION_POLICY_SID_<ENV>` in secrets.
   - Enable **SIP REFER** and **PSTN Transfer** on the trunk (Twilio Console → Elastic SIP Trunking → Manage → Trunks → Termination). This is required for LiveKit `transfer_sip_participant` APIs to succeed during human handoff.

4. **Create LiveKit Voice Agent preset**
   - Use LiveKit Agents dashboard or CLI to define the agent (LLM, STT/TTS, VAD, tools).
   - Record agent ID in `.env` (`LIVEKIT_SIP_VOICE_AGENT_ID_<ENV>`).

5. **Populate health-check call target**
   - Choose an auto-answer test DID or voicemail path per environment.
   - Update `.env` entries (`LIVEKIT_SIP_HEALTH_CALL_TO_<ENV>`, optional DTMF/pin) and mirror to GitHub secrets.
   - Clear legacy Twilio `voiceUrl`/`smsUrl` values on each DID after attaching it to the Elastic SIP trunk so traffic can only enter through the trunk.

6. **Sync secrets**
   - Update `infra/secrets/.env`, your secure vault, and GitHub Actions secrets (see `infra/secrets/README.md`) immediately after provisioning to keep tooling consistent.

7. **Load agent configs at runtime**
   - Services that launch LiveKit Agents must read from `infra/voice-agents/<env>.json` using `@ordering-intelligence/voice-agent-config` so location-specific overrides (`stores.voice_profile.location_code`) are applied consistently. There is no LiveKit preset API today, so this loader is the canonical source of agent instructions/voices. See `docs/voice-agent-worker-deployment.md` for the LiveKit Cloud deployment workflow.
   - Keep the dispatch rule metadata + Firestore data in sync via the helper scripts:
     - `npm run --prefix tests/e2e sip:update-metadata -- --location-code fr-paris`
     - `npm run --prefix tests/e2e voice:set-profile -- --document-id store_123 --location-code fr-paris`
    - The worker now calls `RoomServiceClient.deleteRoom` on shutdown to prevent orphaned rooms. Confirm LiveKit Cloud deploy logs show the `voice-agent-worker:cleanup` message after synthetic calls.

## 7. Testing & Monitoring Requirements

- Nightly GitHub Actions workflow `.github/workflows/sip-health.yml` runs `npm run sip:validate -- --run-call --call-timeout=60000` for dev/staging/prod, pulling LiveKit/Twilio identifiers from encrypted repository secrets (mirror of `infra/secrets/.env`). This checks inbound/dispatch configuration and optionally places a LiveKit-initiated call through the outbound trunk (with DTMF if required).
- SIPp scenarios for load/regression (attach to staging GitHub Actions workflow).
- Synthetic Twilio call runner exercises the `<Dial><Sip>` path exclusively (legacy webhook removed).
- Infra workflow `.github/workflows/infra-livekit.yml` can be triggered manually to run the Twilio Terraform plan and (optionally) deploy or rotate the LiveKit hosted agent.
- Metrics to watch: `LiveKit.SIP.DispatchMatched`, `sip.callStatus`, Twilio trunk error rates, agent VAD start latency.

## 8. Runbook & Communication Updates

- `ops/runbooks/telephony-outage.md` now includes SIP trunk verification steps (Twilio + LiveKit) and fallback instructions.
- Incident template should capture trunk IDs + dispatch rule IDs for any outage impacting routing.
- Notify customers before prod cutover and document reversible steps (switch back Twilio origination to webhook URL).

## 9. Outstanding Tasks

- [ ] Create Twilio Connection Policies / Voice Apps per environment and record their SIDs (`TWILIO_CONNECTION_POLICY_SID_<ENV>`).
- [ ] Stand up LiveKit Voice Agent presets per environment and capture `LIVEKIT_VOICE_AGENT_ID_<ENV>`.
- [ ] Populate credential table above once provisioning completes.
- [ ] Update Terraform modules to store trunk IDs/agent IDs in Secret Manager.
- [ ] Ensure #telephony-alerts Slack channel receives LiveKit SIP webhook notifications.

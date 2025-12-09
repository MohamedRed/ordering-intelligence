# Runbook: Telephony Outage (Twilio SIP / LiveKit SIP)

## Detection
- PagerDuty alerts:
  - `livekit_sip_dispatch_failures > 3/min` or `livekit_agent_room_creation_failures > 3/min`.
  - Synthetic SIP job failure (`lk sip participant create` nightly/hourly).
- Twilio status page notifications for Elastic SIP Trunking.
- LiveKit Cloud status page / webhook alerts.

## Immediate Actions
1. **Acknowledge** the incident in PagerDuty and announce investigation in `#ops`.
2. **Pull current IDs** for the impacted environment (from `infra/secrets/.env` or your secrets vault) so you can reference the right trunks/dispatch rules/agents during triage.

## Triage Checklist
1. **Scope the impact**
   - Cloud Monitoring dashboard `Telephony > SIP` for spikes in `sip.callStatus=hangup` or dispatch failures.
   - Query Firestore `call_sessions` for latest entries (look for repeated failure metadata).
2. **Twilio SIP Trunk Health**
   - Run `twilio api trunking v1 trunks list` (or inspect the console) and confirm the trunk SID configured for the environment is `Active`.
   - Check associated connection policy / `<Dial><Sip>` application for recent errors.
   - If registration or origination fails, route affected numbers to human fallback DID (Admin app toggle or Twilio console).
3. **LiveKit SIP Trunk Health**
   - `lk sip inbound list` → ensure the trunk referenced in `infra/secrets/.env` is `ENABLED`.
   - `lk sip dispatch list --trunk <trunk_id>` → confirm dispatch rule(s) still linked and pins correct.
   - `lk sip participant create` (with staging DID) to reproduce; watch `sip.callStatus`.
4. **Voice Agent & Room**
   - Check LiveKit Agent logs (Cloud Monitoring / LiveKit UI) for VAD start failures or auth issues.
   - Restart agent workers if they stopped pulling tasks.
5. **Human fallback (if needed)**
   - Update Twilio connection policy to route affected numbers to the staffed backup DID if SIP path is down longer than 15 minutes.
   - Announce fallback and confirm traffic resumes (monitor Twilio call logs + LiveKit room creation halting).

## Mitigation & Communication
1. **Customer path**
   - If no automated fallback available, push notification via Notification service `/notify` endpoint to affected tenants with alternate phone instructions.
2. **Secure trunking / region pinning issues**
   - If errors reference region compliance (403 Domestic Anchored), verify `destination_country` on outbound trunk or region-specific endpoint on inbound trunk.
3. **Comms**
   - Update public status page for incidents >10 minutes.
   - Provide ETA + workaround to Support, include Twilio trunk SID + LiveKit trunk ID in notes.

## Recovery
1. Restore SIP routing once providers confirm stability.
2. Run synthetic checks:
   - `lk sip participant create` (staging + prod test DID).
   - Twilio `<Dial><Sip>` manual test call.
3. Watch metrics for 30 minutes to ensure call success rate returns to baseline.

## Post-Incident
1. File incident report (timeline, root cause, detection gaps).
2. Capture trunk IDs/dispatch IDs involved for audit.
3. Open Jira tasks for mitigations (e.g., additional regions, better alerting, automation to flip Twilio routing).

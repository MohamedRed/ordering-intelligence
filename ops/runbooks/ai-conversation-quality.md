# Runbook: AI Conversation Quality Review

## Objective
Assess call transcripts and outcomes to identify issues with ASR accuracy, LLM prompts, or business rule enforcement.

## Preconditions
- Access to Firestore `call_sessions` collection and Cloud Storage audio recordings.
- Access to OpenAI/LLM dashboard for prompt adjustments.
- PagerDuty or Slack channel for operator collaboration.

## Steps
1. **Identify candidate sessions**
   - Query BigQuery `call_metrics` table for calls with confidence < 0.7 or escalations.
   - Retrieve `call_session_id`, tenant, and timestamp.
2. **Review transcript and audio**
   - Open Firestore document `call_sessions/{id}` to view message history.
   - Download audio snippet from Cloud Storage if clarification required.
3. **Categorize issue**
   - ASR misrecognition
   - LLM misunderstanding (prompt or guardrail)
   - Menu/catalog mismatch
   - Telephony/network latency
   - Customer behaviour / background noise
4. **Remediate**
   - Update prompt configuration in orchestrator (via Admin app or Firestore config document).
   - Flag menu items for review in business app if mismatch observed.
   - Create GitHub issue if code changes required.
5. **Document outcome**
   - Add note to `call_sessions/{id}` (`qaStatus`, `qaComments`).
   - Update weekly quality summary in Looker dashboard.
6. **Escalate if systemic**
   - Notify on-call engineer if multiple tenants exhibit same failure within 1 hour.
   - Trigger incident response if >15% calls fail or a compliance concern is identified.

## Post-review follow-up
- Ensure prompts/config changes are versioned and deployed through CI/CD.
- Share insights with product/ops team during weekly review meeting.

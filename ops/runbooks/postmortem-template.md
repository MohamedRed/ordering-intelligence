# Incident Postmortem Template

- **Incident ID:** `INC-YYYYMMDD-XX`
- **Date / Timeframe:** Start – End (UTC)
- **Severity:** SEV1/SEV2/SEV3
- **Services Impacted:** e.g., voice-agent (dev), order-service (staging)
- **Incident Commander:** Name
- **Communications:** Slack channel / PagerDuty notes

## Timeline
| Time (UTC) | Event |
| --- | --- |
| 00:00 | Alert triggered |
| 00:05 | IC paged, triage started |
| ... | ... |

## Customer Impact
- What did users experience? (Include duration, number of calls/orders impacted.)
- How was impact detected (alert, support ticket, synthetic test)?

## Root Cause
- Technical root cause (include diagrams/log excerpts).
- Contributing factors (config drift, missing alerts, knowledge gaps).

## Mitigations & Resolution
- Immediate fixes applied.
- Temporary mitigations (feature flag, traffic shift).
- Verification steps.

## Follow-up Actions
| Action | Owner | Priority | Due Date |
| --- | --- | --- | --- |
| Example: tighten Cloud Armor rule to block pattern XYZ | Platform Eng | High | 2025-11-20 |

## Lessons Learned
- What went well?
- What needs improvement (monitoring, runbooks, tooling)?

Store completed postmortems in `ops/runbooks/postmortems/INC-...md` and link them from the incident tracker.

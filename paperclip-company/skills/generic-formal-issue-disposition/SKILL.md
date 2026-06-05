---
kind: skill
slug: generic-formal-issue-disposition
name: Formal Issue Disposition
description: Required completion format for Paperclip issues.
---

# Formal Issue Disposition

Every issue, routine, or proposal must end with a disposition before being
marked done.

## Required Output

Start every disposition with this exact executive block:

```text
Formal disposition:
What to know:
- Verdict: Ready | Not ready | Needs board decision | Blocked | No action needed
- Problem: the concrete problem this issue or workstream was trying to solve
- Key takeaway: one concise sentence
- Evidence: report path, PR, screenshot, batch id, or source reviewed
- Risk: one concise sentence
- Next action: approve, assign follow-up, wait, reject, or no action
```

The `What to know:` block is mandatory because board dashboards and goal maps
use it as the issue-card summary.

After that block, include the audit trail:

- Outcome: completed, blocked, needs approval, or no action needed.
- Evidence reviewed.
- Work performed.
- Decisions made.
- Files, systems, customers, or vendors affected.
- Validation performed.
- Remaining risk.
- Next owner and next action, if any.

## NO-GO Remediation Requirement

A `Not ready`, `Blocked`, or NO-GO outcome must include a remediation plan. Do
not stop at reporting the problem and waiting for the board to invent the
solution.

For each NO-GO/blocking item, include:

- recommended fix or option set;
- recommended owner;
- dependencies and sequencing;
- what can run in parallel;
- approval gate, if any;
- evidence required to turn the issue into `Ready`.

If you are allowed to create follow-up issues, create or request them. If you
are not allowed to create them, explicitly ask Company Strategy Hermes to
delegate them with the recommended owner and scope.

Bounded autonomy is the default for safe internal remediation. If the fix is
reversible, uses approved tools, stays within existing budgets/caps, and does
not send, deploy, merge, spend, change secrets/vendors/config, publish claims,
or change employee permissions, create or delegate the follow-up issue instead
of waiting for the board. Use native Paperclip blockers/dependencies when the
parent must wait for that remediation.

## Executive Artifact Standard

Goal Maps is for board-speed review. The board should understand what was
done, what changed, what is blocked, and what to decide next without reading
every issue thread.

For every substantive issue, routine, report, or review, provide one
artifact-native visual whenever feasible. Save renderable PNG/JPG/WebP/SVG
artifacts under the configured company artifacts directory, normally
`$AI_COMPANY_ARTIFACTS_DIR/<issue-id>/`, and cite the absolute paths in the
`Evidence:` line or immediately after the executive block. LexPrive
specializations may map this to `$LEXPRIVE_LOCAL_ARTIFACTS_DIR`. Paperclip Goal
Maps can render those images on the goal overview.

An artifact-native visual is a view of the actual work product or evidence,
not a decorative illustration and not a picture of the `What to know:` block.
The visual should answer at least one executive question in a glance: what
changed, what was found, what failed, what remains blocked, or what decision is
required.

Use the visual type that matches the work:

- UI/product/demo: real screenshots, annotated screenshots, before/after views,
  or contact sheets.
- Code/backend/infrastructure: PR or diff summary, changed-file map,
  validation matrix, deployment topology, or before/after behavior evidence.
- Lead/data/outbound: candidate-quality matrix, completeness bars, segment
  counts, suppression-check status, or launch gate table.
- Sales/marketing/copy: before/after copy table, CTA matrix, claim safety
  table, or campaign readiness gate.
- Legal/compliance/security: claim-to-evidence matrix, allowed/blocked claims
  table, risk register, control checklist, or validation matrix.
- Finance/ops: cost/cap table, control board, approval state map, or budget
  variance table.
- QA: test matrix, pass/fail screenshot set, reproduction trace, or validation
  risk heatmap.
- Strategy/CEO: decision map, dependency map, blocker cascade, GO/NO-GO board
  pack, or ownership/next-action map.

Do not claim screenshot or visual evidence is available unless the referenced
file exists and is readable from a Paperclip-mounted path. If no useful visual
is possible, say why and use a compact table, Mermaid diagram, risk matrix, or
status map instead.

The Hermes worker wrapper verifies cited artifact paths after each run. A
disposition that cites a missing artifact path is expected to fail the run, so
create and verify the file first, then cite it.

Do not claim completion when validation failed, approval is missing, or the
assigned action was only partially completed.

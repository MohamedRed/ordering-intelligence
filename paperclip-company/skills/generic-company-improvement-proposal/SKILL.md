---
kind: skill
slug: generic-company-improvement-proposal
name: Company Improvement Proposal
description: Creates board-review proposals for improving the company itself.
---

# Company Improvement Proposal

Use this skill when a recurring signal suggests the company should improve its
org chart, routines, prompts, tools, budgets, policies, memory, or operating
model.

## Proposal Fields

- Type: new employee, prompt improvement, memory update, routine improvement,
  tooling gap, product feedback, ops risk, compliance risk, or finance/cost
  concern.
- Evidence.
- Expected benefit.
- Risks.
- Budget impact.
- Recommended owner.
- Exact approval requested.

Prefer fewer, higher-quality proposals. Do not create work for its own sake.

## Board Approval Card

Every proposal that requires board approval must create or link a native
Paperclip approval object so the board sees Approve/Reject controls in the
dashboard. Use Paperclip's native hire approval path for new employees and
`request_board_approval` for all other board-gated decisions, including
strategy, memory, budget, tool, campaign, production, vendor, security, and
policy changes.

Comments, issue status changes, and chat messages are not sufficient approval
records unless the board explicitly directs an operator to treat one as an
exceptional approval.

## Memory Update Proposals

Paperclip is the source of truth for decisions and approvals. Hermes memory is
only an execution aid for approved reusable lessons.

For a memory update, include:

- Target agent.
- Memory type: lesson, rule, playbook, or blocked claim.
- Source issue or run.
- Proposed memory text.
- Evidence that the lesson is reusable.
- Risk of applying it too broadly.
- Exact approval requested from the board.

Do not write durable Hermes memory directly. Create the Paperclip proposal and
wait for the linked Paperclip approval to be approved.

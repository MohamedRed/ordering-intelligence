---
schema: agentcompanies/v1
kind: task
slug: build-ordering-intelligence-mvp-plan
name: Build Ordering Intelligence MVP operating plan
project: ordering-intelligence
assignee: product-lead-hermes
metadata:
  specializes: generic-ai-native-company
  specialization: ordering-intelligence
  repository: MohamedRed/ordering-intelligence
---

# Build Ordering Intelligence MVP Operating Plan

Create the first implementation and operating plan for Ordering Intelligence. Use the inherited generic product, engineering, compliance, growth, customer, and release workflows, with the specialization team supplying domain constraints.

## Expected Output

- MVP scope and non-goals.
- Domain data model and source-of-truth plan.
- Service/API or workflow outline.
- Review-state, approval-gate, and claim-safety policy.
- Engineering work breakdown with owners.
- Validation plan and known risks.

## Constraints

- Do not change live menu prices, availability, promotions, or POS mappings without approval.
- Separate order data, demand assumptions, and model inference.
- Protect customer, restaurant, payment, and order history data.
- Do not send customer campaigns or operational commands without approval.

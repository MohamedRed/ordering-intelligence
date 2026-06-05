---
schema: agentcompanies/v1
kind: company
slug: ordering-intelligence-ai-company
name: Ordering Intelligence AI Company
description: Builds restaurant ordering intelligence workflows for menus, POS integrations, demand analytics, operations, and customer ordering.
version: 0.1.0
license: UNLICENSED
extends: generic-ai-native-company
tags:
  - generic-ai-native-company
  - specialization
  - ordering-intelligence
  - paperclip
  - hermes
includes:
  - agents/ceo-hermes/AGENTS.md
  - agents/chief-of-staff-hermes/AGENTS.md
  - agents/content-outbound-hermes/AGENTS.md
  - agents/cto-hermes/AGENTS.md
  - agents/customer-research-hermes/AGENTS.md
  - agents/customer-success-hermes/AGENTS.md
  - agents/demand-analytics-hermes/AGENTS.md
  - agents/design-hermes/AGENTS.md
  - agents/devops-sre-hermes/AGENTS.md
  - agents/engineering-lead-hermes/AGENTS.md
  - agents/finance-ops-hermes/AGENTS.md
  - agents/growth-analytics-hermes/AGENTS.md
  - agents/growth-lead-hermes/AGENTS.md
  - agents/hr-recruiting-hermes/AGENTS.md
  - agents/learning-hermes/AGENTS.md
  - agents/learning-strategy-hermes/AGENTS.md
  - agents/legal-compliance-hermes/AGENTS.md
  - agents/market-research-hermes/AGENTS.md
  - agents/marketing-hermes/AGENTS.md
  - agents/menu-data-hermes/AGENTS.md
  - agents/outbound-hermes/AGENTS.md
  - agents/partnerships-hermes/AGENTS.md
  - agents/pos-integrations-hermes/AGENTS.md
  - agents/product-lead-hermes/AGENTS.md
  - agents/qa-engineer-hermes/AGENTS.md
  - agents/qa-release-hermes/AGENTS.md
  - agents/release-engineer-hermes/AGENTS.md
  - agents/restaurant-ops-hermes/AGENTS.md
  - agents/sales-hermes/AGENTS.md
  - agents/security-compliance-hermes/AGENTS.md
  - agents/software-engineer-hermes/AGENTS.md
  - agents/staff-engineer-hermes/AGENTS.md
  - agents/staff-reviewer-hermes/AGENTS.md
  - agents/support-triage-hermes/AGENTS.md
  - projects/ordering-intelligence/PROJECT.md
  - skills/autoplan/SKILL.md
  - skills/benchmark/SKILL.md
  - skills/browse/SKILL.md
  - skills/canary/SKILL.md
  - skills/careful/SKILL.md
  - skills/codex/SKILL.md
  - skills/cso/SKILL.md
  - skills/design-consultation/SKILL.md
  - skills/design-review/SKILL.md
  - skills/document-release/SKILL.md
  - skills/freeze/SKILL.md
  - skills/generic-board-approval-protocol/SKILL.md
  - skills/generic-budget-cost-review/SKILL.md
  - skills/generic-company-improvement-proposal/SKILL.md
  - skills/generic-customer-impact-review/SKILL.md
  - skills/generic-formal-issue-disposition/SKILL.md
  - skills/generic-lead-outreach-operating-model/SKILL.md
  - skills/generic-routine-execution/SKILL.md
  - skills/generic-sensitive-action-escalation/SKILL.md
  - skills/gstack-engineering-plan-review/SKILL.md
  - skills/gstack-product-ceo-review/SKILL.md
  - skills/gstack-qa-canary/SKILL.md
  - skills/gstack-release-readiness/SKILL.md
  - skills/gstack-retrospective/SKILL.md
  - skills/gstack-security-review/SKILL.md
  - skills/gstack-staff-review/SKILL.md
  - skills/gstack-upgrade/SKILL.md
  - skills/guard/SKILL.md
  - skills/investigate/SKILL.md
  - skills/land-and-deploy/SKILL.md
  - skills/office-hours/SKILL.md
  - skills/plan-ceo-review/SKILL.md
  - skills/plan-design-review/SKILL.md
  - skills/plan-eng-review/SKILL.md
  - skills/qa-only/SKILL.md
  - skills/qa/SKILL.md
  - skills/retro/SKILL.md
  - skills/review/SKILL.md
  - skills/setup-browser-cookies/SKILL.md
  - skills/setup-deploy/SKILL.md
  - skills/ship/SKILL.md
  - skills/unfreeze/SKILL.md
  - tasks/build-ordering-intelligence-mvp-plan/TASK.md
  - teams/business-ops/TEAM.md
  - teams/customer/TEAM.md
  - teams/engineering-core/TEAM.md
  - teams/growth/TEAM.md
  - teams/ordering-intelligence-specialization/TEAM.md
  - workflow-templates/customer-issue-escalation.md
  - workflow-templates/engineering-change.md
  - workflow-templates/growth-campaign-change.md
  - workflow-templates/lead-outreach-pipeline.md
  - workflow-templates/new-employee-proposal.md
  - workflow-templates/new-initiative.md
  - workflow-templates/product-change.md
  - workflow-templates/release-to-production.md
  - workflow-templates/security-sensitive-change.md
metadata:
  specializes: generic-ai-native-company
  specializationKind: domain_overlay
  genericAiCompany:
    runtimePolicy: hermes_only
    approvalMode: board_required_for_sensitive_actions
    requiredAdapterType: hermes_local
    gstackUse: composed_engineering_core
    engineeringCoreModule: generic-ai-engineering-core
    growthOperatingModel: vendor_neutral_lead_outreach
  projectSpecialization:
    domain: ordering-intelligence
    repository: MohamedRed/ordering-intelligence
    outputType: reviewable_operating_plan_and_product_workflows
---

# Ordering Intelligence AI Company

This Paperclip company is a specialization of `generic-ai-native-company`. It keeps the generic AI-native operating system intact: CEO governance, product, engineering, growth, customer, operations, compliance, skills, teams, workflow templates, and Hermes-only runtime policy.

The specialization layer adds Ordering Intelligence domain roles and guardrails.

## Inherited Generic Base

- Generic executive, product, engineering, growth, customer, and business-ops agents are included as first-class agents.
- Generic teams, skills, and workflow templates remain part of the package.
- Sensitive work follows the generic board approval and escalation protocol.
- All agents use the Hermes local adapter.

## Ordering Intelligence Specialization Overlay

- Menu Data Hermes: Menu Data Specialist.
- POS Integrations Hermes: POS / Ordering Integrations.
- Demand Analytics Hermes: Demand / Menu Analytics.
- Restaurant Ops Hermes: Restaurant Operations.

## Guardrails

- Do not change live menu prices, availability, promotions, or POS mappings without approval.
- Separate order data, demand assumptions, and model inference.
- Protect customer, restaurant, payment, and order history data.
- Do not send customer campaigns or operational commands without approval.

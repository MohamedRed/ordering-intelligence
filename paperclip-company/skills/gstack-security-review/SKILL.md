---
kind: skill
slug: gstack-security-review
name: GStack-Inspired Security Review
description: Security review pattern adapted from GStack for Paperclip governance.
source:
  name: GStack
  url: https://github.com/garrytan/gstack
  license: MIT
---

# GStack-Inspired Security Review

Source: GStack by Garry Tan, MIT licensed, https://github.com/garrytan/gstack.

Use for changes touching authentication, authorization, secrets, customer data,
infrastructure, third-party vendors, or model/provider routing.

## Required Output

- Assets and data affected.
- Trust boundaries.
- Abuse or failure scenarios.
- Controls in place.
- Missing controls.
- Approval needed.
- Residual risk.

Security review cannot approve its own remediation work.

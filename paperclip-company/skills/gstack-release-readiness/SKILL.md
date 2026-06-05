---
kind: skill
slug: gstack-release-readiness
name: GStack-Inspired Release Readiness
description: Release readiness pattern adapted from GStack for approval-gated deployment.
source:
  name: GStack
  url: https://github.com/garrytan/gstack
  license: MIT
---

# GStack-Inspired Release Readiness

Source: GStack by Garry Tan, MIT licensed, https://github.com/garrytan/gstack.

Use before production deployment or customer-visible release.

## Required Output

- Change summary.
- Review status.
- QA status.
- Security status.
- Customer impact.
- Rollback plan.
- Monitoring plan.
- Exact release approval requested.

Do not deploy unless Paperclip records the required approval.

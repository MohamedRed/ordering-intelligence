# Vendor Onboarding Checklist

1. **Business Justification**
   - Document use case, data types, and regulatory impact.
2. **Security Review**
   - Collect SOC 2 / ISO docs, pen-test summaries, data retention statements.
   - Ensure DPA/SCCs signed if processing customer data.
3. **Access Model**
   - Define least-privilege API keys or accounts per environment.
   - Configure MFA / IP allowlists where supported.
4. **Billing & Monitoring**
   - Tag spend to `ordering-intelligence` cost center.
   - Add usage alerts (PagerDuty + Slack) for budget anomalies.
5. **Operational Runbook**
   - Create incident contacts, escalation paths, and fallback plan.
   - Update `docs/provider-selection.md` Open Items.
6. **Compliance Archive**
   - Store signed contracts in secure repository; link via `docs/compliance/vendor-packages/<vendor>`.

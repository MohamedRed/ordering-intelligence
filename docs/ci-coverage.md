# CI Coverage Thresholds (current)

We enforce pragmatic floors to prevent regressions while keeping pipelines fast. All tests must still pass; thresholds are minimum coverage percentages.

- Menu ingestion (Jest): branches 12, functions 22, lines/statements 27. Config: `backend/services/menu-ingestion/jest.config.cjs`
- Notification service (Jest): branches 22, functions 40, lines/statements 45. Config: `backend/services/notification-service/jest.config.js`
- Voice-agent-worker (c8 + tsx): branches 25, functions 30, lines/statements 35. Config: `backend/services/voice-agent-worker/package.json`
- Go services (order-service, admin-service): CI requires total coverage >= 18% (`backend-ci.yml`). Current: order-service ~18.1%, admin-service ~18.0%.
- Flutter (admin & business): coverage reported in PR summary; thresholds not enforced yet.

Notes:
- Thresholds can be ratcheted up as coverage improves; start from current baseline to avoid blocking merges.
- Coverage reports run automatically in backend CI. Flutter CI already runs `flutter test`; add `--coverage` later if needed.

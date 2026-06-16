# CI Coverage Thresholds (current)

We enforce pragmatic floors to prevent regressions while keeping pipelines fast. All tests must still pass; thresholds are minimum coverage percentages.

- Menu ingestion (Jest): branches 12, functions 22, lines/statements 27. Config: `backend/services/menu-ingestion/jest.config.cjs`
- Notification service (Jest): branches 26, functions 40, lines 34, statements 32. Config: `backend/services/notification-service/jest.config.js`
- Voice-agent-worker (c8 + tsx): branches 25, functions 30, lines/statements 35. Config: `backend/services/voice-agent-worker/package.json`
- Go services: CI requires total coverage >= 10% for admin-service and >= 4% for order-service (`backend-ci.yml`).
- Flutter (admin & business): Flutter CI enforces line coverage >= 30%. Consumer, driver, and telegram-mini run analyze/tests without a coverage floor until baselines are ratcheted.

Notes:
- Thresholds can be ratcheted up as coverage improves; start from current baseline to avoid blocking merges.
- Coverage reports run automatically in backend CI, Flutter CI, and the PR coverage summary workflow.
- Backend CI runs `go vet` for every Go module. Staticcheck is enforced on modules with a clean current baseline; delivery, dispatch, and order-service need a separate deprecated Google client and unused legacy helper cleanup before enabling Staticcheck there.

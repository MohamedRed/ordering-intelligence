# CI Plan (Draft)

## Stages
1) Lint & format
   - gofmt ./backend/services/... (check)
   - npm test in notification-service
   - flutter analyze && flutter test for apps (headless)
2) Unit/contract tests
   - go test ./... for Go services
   - npm test for Node services
3) Security
   - npm audit --production (notification-service)
   - go list -m all | govulncheck (if available)
4) Build
   - docker build order-service, notification-service, admin-service
5) Rules & IaC
   - validate firestore rules (firebase emulators:exec)
6) Deploy
   - deploy to dev via Cloud Build/GitHub Actions

## Env vars to set in CI
- FIRESTORE_PROJECT_ID (for tests needing Firestore emulator)
- ORDER_SERVICE_URL/ADMIN_SERVICE_URL/NOTIFICATION_SERVICE_URL for Flutter integration (point at mocks/emulators)
- GOOGLE_APPLICATION_CREDENTIALS (ci SA) for emulator auth

## Caching
- Flutter/Dart pub cache
- npm cache for notification-service
- Go module cache

## TODO
- Add integration test harness hitting order-service + notification-service with emulators/mocks.
- Add Terraform plan check when IaC repo is present.

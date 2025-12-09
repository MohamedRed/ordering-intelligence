# Client Applications

The Ordering Intelligence platform delivers two Flutter applications backed by Firebase:

- `business/` – Staff-facing app for order intake, menu management, scheduling, and notifications.
- `admin/` – Operator-facing app for tenant onboarding, observability, deployments, and incident response.

Both apps target iOS, Android, and Web (with optional desktop builds for the admin app). Shared Flutter packages and utilities will be managed via Dart `melos` or a similar workspace tool to reduce duplication.

> **Security note:** the CI workflow runs `npm run lint-flutter-https` (see `ops/security`) to block any usage of `http://` URLs or `Uri.http`, and both apps pin the load balancer certificates via `lib/bootstrap/https_pins.dart`. After the managed certificates renew, run `node scripts/update-order-service-pins.mjs` to refresh the fingerprints.

## Roadmap

1. Scaffold Flutter projects with Firebase initialization (Phase 0 completion).
2. Implement authentication, order inbox, and menu editor for the business app (Phase 1).
3. Introduce analytics dashboards, alert management, and deployment controls for the admin app (Phase 2+).

See `docs/ai-ordering-platform-spec.md` Sections 7 and 13 for feature sequencing.

# Admin App (Flutter)

Operator-facing application used by Ordering Intelligence platform administrators to oversee tenants, monitor system health, and receive alerts.

## Planned Features
- Tenant provisioning workflows with configuration review.
- Analytics dashboards summarizing call performance and AI accuracy.
- Live alert feed with acknowledgment workflows and push notifications.
- Menu ingestion review UI to approve OCR/LLM-extracted menu drafts and publish them to stores.
- Deployment controls and feature flag toggles.
- Support for mobile and desktop (Flutter multi-platform).

## Setup
1. Install Flutter >= 3.24 with desktop support as needed.
2. Configure Firebase project (separate from tenant projects where applicable).
3. Install dependencies via `flutter pub get`.
4. Run the app with `flutter run` or `flutter run -d macos` / `-d windows` as required.

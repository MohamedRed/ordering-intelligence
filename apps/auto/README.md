# Auto Apps (CarPlay + Android Auto)

These are native template-based surfaces that depend on the mobile consumer app for identity and data.

## Scope (MVP)
- One-tap reorder to last pickup location.
- Confirmation prompt only (voice optional; feature-flagged).

## Architecture
- Mobile app authenticates the user and creates a session via `/mobile/session/start`.
- Auto clients use the mobile session to call existing reorder/order APIs.
- Mobile app shares the session id to the car app via App Group (iOS) or shared preferences (Android).

## Next steps
- CarPlay sources live in `apps/consumer/ios/Runner/CarPlay/`.
- Configure an App Group and set `CONSUMER_APP_GROUP` in `apps/consumer/ios/Flutter/Secrets.xcconfig`.
- Android Auto sources live in `apps/consumer/android/app/src/main/kotlin/com/orderingintelligence/auto/`.
- Ensure the Android Auto service reads `consumer_session` shared preferences.
- Use the shared session id when calling `/mobile/reorders/recent` and `/mobile/orders`.

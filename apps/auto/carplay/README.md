# CarPlay shell

Files here provide a template-only CarPlay client that consumes the mobile session id
and calls the existing `/mobile/reorders/recent` and `/mobile/orders` endpoints.

Wire-up checklist:
- Add CarPlaySceneDelegate.swift to the iOS target.
- Configure App Group to share the mobile session id (e.g. `group.com.orderingintelligence`).
- Set `CONSUMER_APP_GROUP` in `apps/consumer/ios/Flutter/Secrets.xcconfig`.
- CarPlay uses `CarPlaySessionStore` to read the shared session id.
- Enable the CarPlay template scene in the iOS app's Info.plist.

Source files now live under `apps/consumer/ios/Runner/CarPlay/`.

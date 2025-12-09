# Background Push Handling (implemented)

## Android
- Implemented: `FirebaseMessaging.onBackgroundMessage` shows a local notification via `NotificationService` (`flutter_local_notifications`) with channel `orders`.
- Tap/deeplink: payload `orderId` pushes to order list, highlights, and opens detail screen.

## iOS
- Implemented: permissions requested; background tap handled via `onMessageOpenedApp` + initial message, forwarding `orderId` highlight/deeplink.
- Ensure APNs key/cert configured in Firebase console.

## Payload expectations
- data: `orderId`, `storeId`, `status`
- notification: title/body for tray display

## Remaining polish
- Verify iOS foreground presentation options per App Store review (sound/badge).
- Add analytics event for push tap → order detail open.

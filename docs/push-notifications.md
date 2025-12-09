# Push Notifications

## Topics
- Business app subscribes to `store-{STORE_ID}-orders` for order status events.

## Device tokens
- Business app registers FCM token to notification-service `/device-tokens` (auth required). Stored in Firestore collection `deviceTokens`.

## Foreground UX (to-do)
- Display in-app banner when an order event arrives while app is foregrounded.
- Deep-link to the order inbox; optionally filter/highlight the orderId from message data.

## Background
- OS handles notification tray; ensure Android/iOS notification options set in FirebaseMessaging configuration if adding remote notifications.

## Payload example (order-event)
```
{
  "title": "Order ORD-123 is ready",
  "body": "Alex • total $22.40",
  "data": {"orderId": "ORD-123", "storeId": "demo-store", "status": "ready"}
}
```

## Backend
- notification-service fans out order Pub/Sub events to push/SMS/email; structured logs and metrics available.

## Next steps
- Implement foreground banner + tap-to-open (order list filtered by orderId).
- Add Android/iOS notification channel configuration.

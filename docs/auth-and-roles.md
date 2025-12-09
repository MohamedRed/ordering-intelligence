# Auth & Roles

## Overview
- Clients authenticate with Firebase Auth (ID tokens).
- Backend services verify ID tokens using firebase-admin.
- Admin-only endpoints require `role=admin` claim in the token.

## Claims
- `role`: string. Values: `admin` (operators). Future: `staff`, `owner`.
- (Optional) `storeIds`: string array of store IDs a user can access.
- (Optional) `tenantId`: string.

## Enforcement
- order-service: all routes protected when `REQUIRE_AUTH=true` (default). Accepts any authenticated user (no role check yet).
- admin-service: all routes require `role=admin`.
- notification-service: `/alerts` and `/device-tokens` require a valid token; `/alerts` also checks `role=admin`.

## Environment variables
- `REQUIRE_AUTH` (default `true`): order-service, admin-service.
- `FIRESTORE_PROJECT_ID`, `GOOGLE_APPLICATION_CREDENTIALS`: required for firebase-admin.
- Service URLs for clients:
  - `ORDER_SERVICE_URL`
  - `ADMIN_SERVICE_URL`
  - `NOTIFICATION_SERVICE_URL`
- App constants:
  - `STORE_ID` (business app)

## Device tokens
- Business app registers FCM token to notification-service `/device-tokens` (auth required).
- Tokens stored in Firestore collection `deviceTokens` with fields: token, userId, storeId, platform, updatedAt.

## Topics
- Business app subscribes to `store-{STORE_ID}-orders` for order events.

## How to set claims
Example (Firebase Admin SDK, Node):

```js
await admin.auth().setCustomUserClaims(uid, {
  role: 'admin',
  storeIds: ['demo-store'],
});
```

## Local testing
- `REQUIRE_AUTH=false` can be set to bypass verification (not recommended beyond local dev).

## Open tasks
- Store scoping enforced across order-service (create/list/fetch/status). Keep claims populated.
- Add role checks for business-app specific endpoints if new roles are introduced.

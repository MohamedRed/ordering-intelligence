# Consumer App

Mobile shell for the multi-channel consumer experience. Uses `consumer_core` for shared models
and API calls, plus mobile-only adapters for OAuth, push notifications, and Stripe.

## Quick Start

```bash
flutter pub get
flutter run \
  --dart-define=CHANNEL_GATEWAY_BASE_URL=https://channel-gateway-<env>.run.app \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_xxx \
  --dart-define=FIREBASE_API_KEY=xxx \
  --dart-define=FIREBASE_APP_ID=1:1234567890:ios:abc123 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
  --dart-define=FIREBASE_PROJECT_ID=ordering-intel \
  --dart-define=FACEBOOK_APP_ID=1234567890 \
  --dart-define=DISCORD_CLIENT_ID=xxx \
  --dart-define=DISCORD_REDIRECT_URI=com.orderingintelligence.consumer://oauth \
  --dart-define=SNAPCHAT_CLIENT_ID=xxx \
  --dart-define=SNAPCHAT_REDIRECT_URI=com.orderingintelligence.consumer://oauth \
  --dart-define=TIKTOK_CLIENT_KEY=xxx \
  --dart-define=TIKTOK_REDIRECT_URI=com.orderingintelligence.consumer://oauth
```

## OAuth Redirect Scheme

We use `flutter_web_auth_2` for Discord/Snap/TikTok OAuth. The redirect scheme must match
the native config:

- **Android**: `APP_AUTH_REDIRECT_SCHEME` in `android/gradle.properties`
- **iOS**: `OAUTH_REDIRECT_SCHEME` in `ios/Flutter/Secrets.xcconfig`

Default scheme is `com.orderingintelligence.consumer`, so a typical redirect URI is:
`com.orderingintelligence.consumer://oauth`.

## Facebook Login (native SDK)

### Android

Set these in `android/gradle.properties` (or `~/.gradle/gradle.properties`):

```
FACEBOOK_APP_ID=1234567890
FACEBOOK_CLIENT_TOKEN=xxx
FACEBOOK_DISPLAY_NAME=Ordering Intelligence
APP_AUTH_REDIRECT_SCHEME=com.orderingintelligence.consumer
```

Also pass `--dart-define=FACEBOOK_APP_ID=...` so the sign-in UI enables Facebook.

### iOS

Update `ios/Flutter/Secrets.xcconfig`:

```
FACEBOOK_APP_ID=1234567890
FACEBOOK_CLIENT_TOKEN=xxx
FACEBOOK_DISPLAY_NAME=Ordering Intelligence
OAUTH_REDIRECT_SCHEME=com.orderingintelligence.consumer
CONSUMER_APP_GROUP=group.com.orderingintelligence
```

Enable the **App Groups** and **CarPlay** capabilities for the Runner target in Xcode,
and ensure the App Group matches `CONSUMER_APP_GROUP`.

CarPlay requires entitlements in `ios/Runner/Runner.entitlements`:
- `com.apple.security.application-groups` (App Group)
- `com.apple.developer.carplay-quick-ordering` (requires Apple approval)

For CI, you can sync the App Group into entitlements via:
`scripts/ios/sync_entitlements.sh`

Also pass `--dart-define=FACEBOOK_APP_ID=...` so the sign-in UI enables Facebook.

## Push Notifications (FCM)

The app registers device tokens with channel-gateway. To enable delivery:

- Configure APNs + Push Notifications capability in the Apple developer portal.
- Add `GoogleService-Info.plist` (iOS) / `google-services.json` (Android) if your Firebase
  project uses the standard config flow.
- Ensure the Firebase project has APNs auth key and FCM enabled.

## Auto App Session Sharing

The mobile app mirrors the current session into native shared storage so CarPlay/Android Auto
can read it.

- **Android**: stored in SharedPreferences named `consumer_session`.
- **iOS**: stored in `UserDefaults` using the App Group set in `CONSUMER_APP_GROUP`
  (falls back to standard defaults if empty).

## Auto App Wiring

- **Android Auto**: service + UI live in
  `apps/consumer/android/app/src/main/kotlin/com/orderingintelligence/auto/`.
  The manifest already registers `OrderingCarAppService` and `automotive_app_desc.xml`.
- **CarPlay**: sources live in `apps/consumer/ios/Runner/CarPlay/`.
  The Info.plist includes the CarPlay scene; ensure the CarPlay capability + App Group
  entitlement are enabled in Xcode.

The mobile app includes an **Auto diagnostics** screen (car icon) to verify the
shared session id and FCM token.

## Environment Flags

- `ALLOW_MOCK_AUTH=true|false` (defaults to `true`)
- `CHANNEL_GATEWAY_BASE_URL`
- `MOBILE_SESSION_SHARED_SECRET` (optional; enables signed session invalidation)
- `STRIPE_PUBLISHABLE_KEY`
- `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`
- OAuth provider keys + redirect URIs

## TV / Living‑Room Shell (beta)

- Entry point: `apps/consumer/lib/main_tv.dart`
- Uses the same feature set with TV-friendly focus navigation, larger type, and a glass backdrop.
- Run on web/desktop emulator:
  ```bash
  flutter run -t lib/main_tv.dart -d chrome
  ```
- Android TV / Google TV:
  ```bash
  flutter run -t lib/main_tv.dart -d android-tv
  ```
- tvOS: create a tvOS Runner target and launch with `-t lib/main_tv.dart`; remote focus is enabled by default.
- Fire TV (Amazon Appstore build):
  ```bash
  flutter build apk -t lib/main_tv.dart --flavor firetv --release
  ```

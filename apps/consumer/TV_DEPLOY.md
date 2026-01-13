# Consumer TV / Living‑Room Deploy Guide

This covers shipping the consumer experience to Android TV / Google TV, Amazon Fire TV, Apple tvOS, and Roku.
The Flutter TV shell (`lib/main_tv.dart`) handles Android TV / Fire TV / tvOS; Roku needs a native channel.

## Android TV / Google TV
- Entry: `flutter run -t lib/main_tv.dart -d android-tv`
- Use the existing `main_tv.dart` (focus nav, large type, glass backdrop).
- Store: Google Play (TV); set `uses-feature android.software.leanback` in the Android manifest (already present via Flutter TV builds).
- Auth/Pay: Pairing via `/tv/pair/start` (QR + code) → mobile app deep link for OAuth + Stripe.
- Testing: Fire up an Android TV emulator or physical Chromecast w/Google TV.

## Amazon Fire TV
- Fire TV is Android-based; reuse `lib/main_tv.dart`.
- Build an Amazon Appstore bundle (APK): `flutter build apk -t lib/main_tv.dart --flavor firetv --release`.
- Ensure Leanback launcher icons and Amazon Store listing assets.
- Auth/Pay: Same `/tv/pair/start` QR + code pairing to mobile for OAuth + Stripe; avoid card entry on TV.
- Distribution: Upload via Amazon Developer Console; mark as Fire TV app.

## Apple tvOS
- Requires a tvOS Runner target; set the entrypoint to `lib/main_tv.dart`.
- Enable remote focus navigation (already in `_TvScrollBehavior` + `FocusTraversalGroup`).
- Auth/Pay: `/tv/pair/start` QR + code to mobile deep link; no direct card input.
- Distribution: Apple TV app, paired with your existing bundle ID family.

## Roku (native channel required)
- Skeleton lives in `apps/consumer/roku-channel/` (SceneGraph + BrightScript).
  - Current state: pairing QR + code from `/tv/pair/start`; polls `/tv/pair/state` for session token.
  - Auth/Pay: QR → mobile deep link to complete OAuth + Stripe; channel stores a short‑lived session token from channel-gateway.
  - APIs: reuse channel-gateway and consumer_core endpoints; add thin JSON endpoints for Roku payloads as needed.
  - Media: avoid heavy maps/video; prefer static cards + progress states.
- Packaging: zip and sideload for dev; submit via Roku Developer Dashboard when pairing + grids are complete.

## Common UX rules for TV
- Keep CTAs high-contrast; large hit targets; strong focus states.
- Always offer “open on phone” for payment, login, and long text input.
- Limit background blur on low-end sticks; reduce `blurSigma` in `GlassBackdrop` if perf drops.

## Next steps (suggested)
1) Add a Fire-TV specific product flavor for Amazon signing assets.
2) Add tvOS Runner target pointing to `lib/main_tv.dart`.
3) Stand up a minimal Roku channel skeleton in `apps/consumer/roku-channel/` (SceneGraph) that hits a pairing endpoint.

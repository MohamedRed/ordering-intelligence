# Driver App

Driver-facing Flutter app for owned-fleet dispatch.

## Features (v1)

- Phone auth (Firebase).
- Claim driver record by phone number.
- Marketplace courier mode with Stripe Express payout onboarding.
- Shift start/pause/end.
- Manual and auto location updates (foreground).
- Accept/decline assignments.
- View current route and mark stop status.

## Notes

- Auto location uses an Android foreground service notification; true background execution still requires a dedicated background isolate (planned).
- For iOS background location, ensure the iOS target includes `UIBackgroundModes` with `location` and `NSLocationAlwaysAndWhenInUseUsageDescription`/`NSLocationWhenInUseUsageDescription` entries in `Info.plist`.

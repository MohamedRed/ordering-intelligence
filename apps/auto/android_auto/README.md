# Android Auto shell

Skeleton implementation for Android Auto template UI.

Wire-up checklist:
- Add OrderingCarAppService to the Android manifest.
- Ensure the Android app and Auto service share the same package name.
- Android Auto reads the session id from `consumer_session` SharedPreferences.
- Add required Android Auto dependencies (`androidx.car.app:app`) in the Android app module.

Source files now live under `apps/consumer/android/app/src/main/kotlin/com/orderingintelligence/auto/`.

## QA (Desktop Head Unit)

1. Enable Android Auto developer mode and "Unknown sources".
2. Install the debug build on a device (or emulator with Google Play services).
3. Run the Desktop Head Unit (DHU) from the Android SDK:
   - `adb forward tcp:5277 tcp:5277`
   - `./desktop-head-unit` (from `sdk/extras/google/auto`)
4. Launch the Ordering Intelligence app on the phone to ensure a session is stored.
5. The Auto UI should appear in DHU under the app list.

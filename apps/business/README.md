# Business App (Flutter)

Staff-facing client that provides real-time order inbox, menu management, schedule controls, and notifications.

## Planned Features (Phase 1)
- Firebase Authentication with role-based access.
- Live order feed sourced from Firestore & Cloud Functions.
- Menu editor supporting categories, modifiers, and availability toggles.
- Push notifications for new orders and escalations.
- Offline caching with Firestore local persistence.

## Project Setup
1. Install Flutter >= 3.24 and enable web support.
2. Configure Firebase project and run `flutterfire configure` to generate platform files.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

> **Note:** Platform-specific directories (`android/`, `ios/`, etc.) are omitted until `flutter create` or `flutterfire` tooling is executed in the target environment.

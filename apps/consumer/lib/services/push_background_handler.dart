import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = firebaseOptionsFromEnv();
  if (options == null || Firebase.apps.isNotEmpty) {
    return;
  }
  await Firebase.initializeApp(options: options);
}

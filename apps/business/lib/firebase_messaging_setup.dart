import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'notification_service.dart';

Future<void> initFirebaseAndMessaging() async {
  await Firebase.initializeApp(options: firebaseOptions);
  final messaging = FirebaseMessaging.instance;

  // Request permissions on iOS/macOS (skip on web where Platform is unsupported).
  if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
    await messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

Future<void> backgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.init();
  await NotificationService.instance.showRemoteMessage(message);
}

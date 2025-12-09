import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'notification_service.dart';

Future<void> initFirebaseAndMessaging() async {
  await Firebase.initializeApp(options: firebaseOptions);
  final messaging = FirebaseMessaging.instance;

  // Request permissions on iOS/macOS.
  if (Platform.isIOS || Platform.isMacOS) {
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

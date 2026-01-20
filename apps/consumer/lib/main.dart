import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app/consumer_app.dart';
import 'bootstrap/ci_semantics.dart';
import 'firebase_options.dart';
import 'services/push_background_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableCiSemantics();
  final options = firebaseOptionsFromEnv();
  if (options != null) {
    await Firebase.initializeApp(options: options);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  runApp(const ConsumerApp());
}

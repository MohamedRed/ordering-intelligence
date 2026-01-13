import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;

const _notificationServiceUrl = String.fromEnvironment(
  'NOTIFICATION_SERVICE_URL',
  defaultValue: 'https://notification-service-f2qwyitacq-uc.a.run.app',
);

Future<String?> fetchFcmToken() async {
  return FirebaseMessaging.instance.getToken();
}

Future<void> registerTokenWithBackend({
  required String token,
  required String storeId,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final idToken = user != null ? await user.getIdToken() : null;
  if (idToken == null) return;
  try {
    final resp = await http.post(
      Uri.parse('$_notificationServiceUrl/device-tokens'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'token': token,
        'storeId': storeId,
        'platform': 'flutter',
      }),
    );
    if (resp.statusCode != 204) {
      // ignore: avoid_print
      print('Token register failed: ${resp.statusCode} ${resp.body}');
    }
  } catch (e) {
    // ignore: avoid_print
    print('Token register error: $e');
  }
}

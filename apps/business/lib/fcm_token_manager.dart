import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

const _notificationServiceUrl = String.fromEnvironment(
  'NOTIFICATION_SERVICE_URL',
  defaultValue:
      'https://notification-service-f2qwyitacq-uc.a.run.app',
);
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

final fcmTokenProvider = FutureProvider<String?>((ref) async {
  final token = await FirebaseMessaging.instance.getToken();
  return token;
});

Future<void> subscribeToStoreTopic(String storeId) async {
  if (kIsWeb) return; // Web FCM SDK doesn't support topics.
  final topic = 'store-$storeId-orders';
  await FirebaseMessaging.instance.subscribeToTopic(topic);
}

Future<void> registerTokenWithBackend(String token) async {
  final user = FirebaseAuth.instance.currentUser;
  final idToken = user != null ? await user.getIdToken() : null;
  if (idToken == null) {
    // Not signed in; skip registration to avoid 401 spam.
    return;
  }
  try {
    final resp = await http.post(
      Uri.parse('$_notificationServiceUrl/device-tokens'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'token': token,
        'storeId': _storeId,
        'platform': 'flutter',
      }),
    );
    if (resp.statusCode != 204) {
      // Non-fatal in dev: log and move on.
      // ignore: avoid_print
      print('Token register failed: ${resp.statusCode} ${resp.body}');
    }
  } catch (e) {
    // In dev/local web, notification service might be unreachable; ignore.
    // ignore: avoid_print
    print('Token register error: $e');
  }
}

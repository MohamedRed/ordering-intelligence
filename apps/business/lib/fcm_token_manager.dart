import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const _notificationServiceUrl = String.fromEnvironment(
    'NOTIFICATION_SERVICE_URL',
    defaultValue: 'http://localhost:8084');
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

final fcmTokenProvider = FutureProvider<String?>((ref) async {
  final token = await FirebaseMessaging.instance.getToken();
  return token;
});

Future<void> subscribeToStoreTopic(String storeId) async {
  final topic = 'store-$storeId-orders';
  await FirebaseMessaging.instance.subscribeToTopic(topic);
}

Future<void> registerTokenWithBackend(String token) async {
  final resp = await http.post(
    Uri.parse('$_notificationServiceUrl/device-tokens'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'token': token,
      'storeId': _storeId,
      'platform': 'flutter',
    }),
  );
  if (resp.statusCode != 204) {
    throw Exception('Failed to register token: ${resp.statusCode}');
  }
}

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/alert.dart';

const _baseUrl = String.fromEnvironment('NOTIFICATION_SERVICE_URL',
    defaultValue: 'http://localhost:8084');

class AlertApi {
  final http.Client _client;
  AlertApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<AlertItem>> fetchAlerts() async {
    final token = await _token();
    final resp = await _client.get(Uri.parse('$_baseUrl/alerts'),
        headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load alerts: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => AlertItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, String> _headers(String? token) {
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }
}

final alertApiProvider = Provider<AlertApi>((ref) => AlertApi());
final alertsProvider = FutureProvider<List<AlertItem>>((ref) async {
  final api = ref.watch(alertApiProvider);
  return api.fetchAlerts();
});

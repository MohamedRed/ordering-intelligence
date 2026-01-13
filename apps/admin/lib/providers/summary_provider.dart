import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/summary.dart';

// Default to deployed dev service; override with --dart-define=ORDER_SERVICE_URL=http://localhost:8082 when running locally.
const _orderServiceUrl = String.fromEnvironment(
  'ORDER_SERVICE_URL',
  defaultValue: 'https://order-service-230152279015.us-central1.run.app',
);
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

class SummaryApi {
  final http.Client _client;
  SummaryApi({http.Client? client}) : _client = client ?? http.Client();

  Future<OrderSummary> fetchSummary() async {
    final token = await _token();
    final resp = await _client.get(
      Uri.parse('$_orderServiceUrl/stores/$_storeId/orders/summary'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load summary: ${resp.statusCode}');
    }
    return OrderSummary.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
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

final summaryApiProvider = Provider<SummaryApi>((ref) => SummaryApi());
final orderSummaryProvider = FutureProvider<OrderSummary>((ref) async {
  final api = ref.watch(summaryApiProvider);
  return api.fetchSummary();
});

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';

const _baseUrl = String.fromEnvironment('ORDER_SERVICE_URL', defaultValue: 'http://localhost:8082');

class OrderDetailApi {
  final http.Client _client;
  OrderDetailApi({http.Client? client}) : _client = client ?? http.Client();

  Future<Order> fetchOrder(String orderId) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final resp = await _client.get(
      Uri.parse('$_baseUrl/orders/$orderId'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load order: ${resp.statusCode} ${resp.body}');
    }
    return Order.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}

final orderDetailApiProvider = Provider<OrderDetailApi>((ref) => OrderDetailApi());

final orderDetailProvider = FutureProvider.family<Order, String>((ref, orderId) async {
  final api = ref.watch(orderDetailApiProvider);
  return api.fetchOrder(orderId);
});

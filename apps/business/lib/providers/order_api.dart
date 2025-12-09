import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';
import 'offline_queue.dart';

const _baseUrl = String.fromEnvironment('ORDER_SERVICE_URL',
    defaultValue: 'http://localhost:8082');
const _storeId = String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');

class OrderApi {
  final http.Client _client;
  OrderApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(_baseUrl + path).replace(queryParameters: query);

  Future<List<Order>> listOrders({String status = ''}) async {
    final token = await _token();
    final uri = _uri('/stores/$_storeId/orders',
        status.isNotEmpty ? {'status': status} : null);
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load orders: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> updateStatus(String orderId, OrderStatus status) async {
    final token = await _token();
    final uri = _uri('/orders/$orderId/status');
    final resp = await _client.patch(
      uri,
      headers: _headers(token),
      body: jsonEncode({'status': _statusToString(status)}),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to update status: ${resp.statusCode} ${resp.body}');
    }
    return Order.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  String _statusToString(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.ready:
        return 'ready';
      case OrderStatus.completed:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
    }
  }

  OrderStatus stringToStatus(String value) {
    switch (value) {
      case 'pending':
        return OrderStatus.pending;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'ready':
        return OrderStatus.ready;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
      default:
        return OrderStatus.cancelled;
    }
  }

  Map<String, String> _headers(String? token) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<String?> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    return user != null ? user.getIdToken() : null;
  }
}

class OrderRepository {
  final OrderApi _api;
  OrderRepository({OrderApi? api}) : _api = api ?? OrderApi();
  final _queue = StatusUpdateQueue();

  Future<List<Order>> fetchOrders() => _api.listOrders();
  Future<Order> setStatus(String orderId, OrderStatus status) async {
    try {
      final updated = await _api.updateStatus(orderId, status);
      // If success, also try to flush any queued updates.
      await _flushQueue();
      return updated;
    } catch (_) {
      // enqueue for retry
      await _queue.add(
          QueuedStatus(orderId: orderId, status: _api._statusToString(status)));
      rethrow;
    }
  }

  Future<void> _flushQueue() async {
    await _queue.flush(
      (item) =>
          _api.updateStatus(item.orderId, _api.stringToStatus(item.status)),
    );
  }

  Future<void> flushPending() async {
    await _flushQueue();
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';
import '../models/wait_time.dart';
import 'offline_queue.dart';
import '../util/store_id.dart';

part 'order_api_fuel.dart';
part 'order_api_refund.dart';

const _baseUrl = String.fromEnvironment(
  'ORDER_SERVICE_URL',
  defaultValue: 'https://order-service-230152279015.us-central1.run.app',
);

class OrderApi {
  final http.Client _client;
  OrderApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(_baseUrl + path).replace(queryParameters: query);

  Future<List<Order>> listOrders({String status = ''}) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final uri = _uri('/stores/$storeId/orders',
        status.isNotEmpty ? {'status': status} : null);
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load orders: ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);

    // Some environments return `null` or wrap the list in an `orders` field—
    // handle both gracefully and default to an empty list.
    final list = decoded == null
        ? <dynamic>[]
        : decoded is List
            ? decoded
            : (decoded is Map && decoded['orders'] is List)
                ? decoded['orders'] as List
                : throw Exception('Failed to load orders: unexpected payload');

    return list
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Order> updateStatus(
    String orderId,
    OrderStatus status, {
    String? notifyMode,
    String? note,
    String? templateId,
  }) async {
    final token = await _token();
    final uri = _uri('/orders/$orderId/status');
    final body = <String, dynamic>{'status': orderStatusToString(status)};
    if (notifyMode != null && notifyMode.trim().isNotEmpty) {
      body['notifyMode'] = notifyMode.trim();
    }
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }
    if (templateId != null && templateId.trim().isNotEmpty) {
      body['templateId'] = templateId.trim();
    }
    final resp = await _client.patch(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to update status: ${resp.statusCode} ${resp.body}');
    }
    return Order.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> notifyDelay(
    String orderId, {
    required String notifyMode,
    String? note,
    String? templateId,
  }) async {
    final token = await _token();
    final uri = _uri('/orders/$orderId/customer-comms');
    final body = <String, dynamic>{
      'kind': 'delay',
      'notifyMode': notifyMode.trim().isEmpty ? 'auto' : notifyMode.trim(),
    };
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }
    if (templateId != null && templateId.trim().isNotEmpty) {
      body['templateId'] = templateId.trim();
    }
    final resp = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to notify delay: ${resp.statusCode} ${resp.body}');
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
    return user?.getIdToken();
  }

  Future<WaitTimeSummary> getWaitTimeSummary() async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final uri = _uri('/stores/$storeId/wait-time/summary');
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load wait-time summary: ${resp.statusCode}');
    }
    return WaitTimeSummary.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<WaitTimeDailyResponse> getWaitTimeDaily({int days = 7}) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final uri = _uri('/stores/$storeId/wait-time/daily', {'days': '$days'});
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load wait-time daily: ${resp.statusCode}');
    }
    return WaitTimeDailyResponse.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
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
          QueuedStatus(orderId: orderId, status: orderStatusToString(status)));
      rethrow;
    }
  }

  Future<Order> setStatusWithAction(
    String orderId,
    OrderStatus status, {
    required String notifyMode,
    String? note,
    String? templateId,
  }) async {
    final updated = await _api.updateStatus(
      orderId,
      status,
      notifyMode: notifyMode,
      note: note,
      templateId: templateId,
    );
    // Best-effort flush queued updates after successful call.
    await _flushQueue();
    return updated;
  }

  Future<void> notifyDelayWithAction(
    String orderId, {
    required String notifyMode,
    String? note,
    String? templateId,
  }) async {
    await _api.notifyDelay(
      orderId,
      notifyMode: notifyMode,
      note: note,
      templateId: templateId,
    );
    await _flushQueue();
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

  Future<WaitTimeSummary> fetchWaitTimeSummary() => _api.getWaitTimeSummary();

  Future<WaitTimeDailyResponse> fetchWaitTimeDaily({int days = 7}) =>
      _api.getWaitTimeDaily(days: days);
}

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/group_order.dart';
import '../util/store_id.dart';

const _baseUrl = String.fromEnvironment(
  'ORDER_SERVICE_URL',
  defaultValue: 'https://order-service-230152279015.us-central1.run.app',
);

class GroupOrderApi {
  final http.Client _client;
  GroupOrderApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(_baseUrl + path).replace(queryParameters: query);

  Future<List<GroupOrder>> listGroupOrders({String status = ''}) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final uri = _uri('/stores/$storeId/group-orders',
        status.isNotEmpty ? {'status': status} : null);
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load group orders: ${resp.statusCode}');
    }
    final decoded = jsonDecode(resp.body);
    final list = decoded == null
        ? <dynamic>[]
        : decoded is List
            ? decoded
            : (decoded is Map && decoded['groupOrders'] is List)
                ? decoded['groupOrders'] as List
                : (decoded is Map && decoded['group_orders'] is List)
                    ? decoded['group_orders'] as List
                    : throw Exception(
                        'Failed to load group orders: unexpected payload');

    return list
        .whereType<Map<String, dynamic>>()
        .map(GroupOrder.fromJson)
        .toList(growable: false);
  }

  Future<GroupOrder> fetchGroupOrder(String groupOrderId) async {
    final token = await _token();
    final storeId = effectiveStoreId();
    final uri = _uri('/stores/$storeId/group-orders/$groupOrderId');
    final resp = await _client.get(uri, headers: _headers(token));
    if (resp.statusCode != 200) {
      throw Exception(
          'Failed to load group order: ${resp.statusCode} ${resp.body}');
    }
    final payload = jsonDecode(resp.body);
    if (payload is Map<String, dynamic>) {
      final raw = payload['groupOrder'];
      if (raw is Map<String, dynamic>) {
        return GroupOrder.fromJson(raw);
      }
      return GroupOrder.fromJson(payload);
    }
    throw Exception('Failed to load group order: unexpected payload');
  }

  Future<GroupOrderRefundResult> refundGroupOrder(
    String groupOrderId, {
    int? amountCents,
    String? reason,
    String? note,
    String? participantId,
    String? paymentId,
  }) async {
    final token = await _token();
    final uri = _uri('/group_orders/$groupOrderId/refund');
    final body = <String, dynamic>{};
    if (amountCents != null && amountCents > 0) {
      body['amountCents'] = amountCents;
    }
    if (reason != null && reason.trim().isNotEmpty) {
      body['reason'] = reason.trim();
    }
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }
    if (participantId != null && participantId.trim().isNotEmpty) {
      body['participantId'] = participantId.trim();
    }
    if (paymentId != null && paymentId.trim().isNotEmpty) {
      body['paymentId'] = paymentId.trim();
    }
    final resp = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to refund: ${resp.statusCode} ${resp.body}');
    }
    return GroupOrderRefundResult.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
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
}

class GroupOrderRefundResult {
  GroupOrderRefundResult({
    required this.amountCents,
    required this.status,
    this.paymentId,
    this.refundId,
    this.paymentStatus,
    this.refundedAmountCents,
  });

  final int amountCents;
  final String status;
  final String? paymentId;
  final String? refundId;
  final String? paymentStatus;
  final int? refundedAmountCents;

  factory GroupOrderRefundResult.fromJson(Map<String, dynamic> json) {
    return GroupOrderRefundResult(
      amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?)?.trim() ?? '',
      paymentId: (json['paymentId'] as String?)?.trim(),
      refundId: (json['refundId'] as String?)?.trim(),
      paymentStatus: (json['paymentStatus'] as String?)?.trim(),
      refundedAmountCents: (json['refundedAmountCents'] as num?)?.toInt(),
    );
  }
}

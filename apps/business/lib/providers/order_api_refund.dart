part of 'order_api.dart';

class OrderRefundResult {
  OrderRefundResult({
    required this.amountCents,
    required this.status,
    this.refundId,
    this.paymentStatus,
  });

  final int amountCents;
  final String status;
  final String? refundId;
  final String? paymentStatus;

  factory OrderRefundResult.fromJson(Map<String, dynamic> json) {
    return OrderRefundResult(
      amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?)?.trim() ?? '',
      refundId: (json['refundId'] as String?)?.trim(),
      paymentStatus: (json['paymentStatus'] as String?)?.trim(),
    );
  }
}

extension OrderApiRefund on OrderApi {
  Future<OrderRefundResult> refundOrder(
    String orderId, {
    int? amountCents,
    String? reason,
    String? note,
  }) async {
    final token = await _token();
    final uri = _uri('/orders/$orderId/refund');
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
    final resp = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to refund: ${resp.statusCode} ${resp.body}');
    }
    return OrderRefundResult.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }
}

extension OrderRepositoryRefund on OrderRepository {
  Future<OrderRefundResult> refundOrder(
    String orderId, {
    int? amountCents,
    String? reason,
    String? note,
  }) async {
    final result = await _api.refundOrder(
      orderId,
      amountCents: amountCents,
      reason: reason,
      note: note,
    );
    await _flushQueue();
    return result;
  }
}

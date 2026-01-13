part of 'order_api.dart';

extension OrderApiFuel on OrderApi {
  Future<Order> completeFuelOrder(
    String orderId, {
    double finalLiters = 0,
    int finalAmountCents = 0,
  }) async {
    final token = await _token();
    final uri = _uri('/orders/$orderId/fuel/complete');
    final body = <String, dynamic>{
      'finalLiters': finalLiters,
      'finalAmountCents': finalAmountCents,
    };
    final resp = await _client.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to complete fuel order: ${resp.statusCode} ${resp.body}');
    }
    return Order.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}

extension OrderRepositoryFuel on OrderRepository {
  Future<Order> completeFuelOrder(
    String orderId, {
    double finalLiters = 0,
    int finalAmountCents = 0,
  }) async {
    final updated = await _api.completeFuelOrder(
      orderId,
      finalLiters: finalLiters,
      finalAmountCents: finalAmountCents,
    );
    await _flushQueue();
    return updated;
  }
}

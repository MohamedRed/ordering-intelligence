part of 'channel_gateway_api.dart';

mixin ChannelGatewayOrderUpdatesApi on ChannelGatewayApiBase {
  Future<OrderUpdatesLink> linkTelegramOrderUpdates({
    required String sessionId,
    required String orderId,
  }) async {
    final response = await _client.post(
      _buildUri('/telegram/webapp/orders/$orderId/link-updates'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Order updates link failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return OrderUpdatesLink.fromJson(payload);
  }
}

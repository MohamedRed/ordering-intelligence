part of 'channel_gateway_api.dart';

mixin ChannelGatewayGroupOrdersCheckoutApi on ChannelGatewayApiBase {
  Future<GroupOrderSession> addGroupOrderItems({
    required String groupOrderId,
    required String sessionId,
    required String participantId,
    String? participantLabel,
    required List<CartItem> items,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/items'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'participantId': participantId,
        if (participantLabel != null) 'participantLabel': participantLabel,
        'items': items.map(mapGroupOrderItem).toList(),
      }),
    );
    return parseGroupOrderResponse(response);
  }

  Future<GroupOrderSession> lockGroupOrder({
    required String groupOrderId,
    required String sessionId,
    int taxCents = 0,
    int feeCents = 0,
    int discountCents = 0,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/lock'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'taxCents': taxCents,
        'feeCents': feeCents,
        'discountCents': discountCents,
      }),
    );
    return parseGroupOrderResponse(response);
  }

  Future<GroupOrderCheckoutResponse> checkoutGroupOrder({
    required String groupOrderId,
    required String sessionId,
    required String successUrl,
    required String cancelUrl,
    String? participantId,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/checkout'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        if (participantId != null) 'participantId': participantId,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Checkout failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return GroupOrderCheckoutResponse.fromJson(payload);
  }
}

part of 'channel_gateway_api.dart';

mixin ChannelGatewayGroupOrdersWriteApi on ChannelGatewayApiBase {
  Future<GroupOrderSession> createGroupOrder({
    required String sessionId,
    required String storeId,
    required String paymentMode,
    required String paymentMethod,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'storeId': storeId,
        'paymentMode': paymentMode,
        'paymentMethod': paymentMethod,
      }),
    );
    return parseGroupOrderResponse(response);
  }

  Future<GroupOrderSession> joinGroupOrder({
    required String groupOrderId,
    required String sessionId,
    required String inviteId,
    String? displayName,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/join'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'inviteId': inviteId,
        if (displayName != null) 'displayName': displayName,
      }),
    );
    return parseGroupOrderResponse(response);
  }

  Future<GroupOrderInvite> createGroupOrderInvite({
    required String groupOrderId,
    required String sessionId,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/invites'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Invite create failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final inviteJson = payload['invite'];
    if (inviteJson is Map<String, dynamic>) {
      return GroupOrderInvite.fromJson(inviteJson);
    }
    return GroupOrderInvite.fromJson(payload);
  }

  Future<GroupOrderSession> submitGroupOrder({
    required String groupOrderId,
    required String sessionId,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/group-orders/$groupOrderId/submit'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId}),
    );
    return parseGroupOrderResponse(response);
  }
}

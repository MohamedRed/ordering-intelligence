part of 'channel_gateway_api.dart';

mixin ChannelGatewayGroupOrdersReadApi on ChannelGatewayApiBase {
  Future<GroupOrderSession> lookupGroupOrderByJoinCode({
    required String joinCode,
  }) async {
    final response = await _client.get(
      _buildWebAppUri('/group-orders/join/$joinCode'),
      headers: const {'Content-Type': 'application/json'},
    );
    return parseGroupOrderResponse(response);
  }

  Future<GroupOrderSession> getGroupOrder({required String groupOrderId}) async {
    final response = await _client.get(
      _buildWebAppUri('/group-orders/$groupOrderId'),
      headers: const {'Content-Type': 'application/json'},
    );
    return parseGroupOrderResponse(response);
  }
}

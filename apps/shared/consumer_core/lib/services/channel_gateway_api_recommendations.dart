part of 'channel_gateway_api.dart';

mixin ChannelGatewayRecommendationsApi on ChannelGatewayApiBase {
  Future<List<RecommendedOrder>> fetchRecommendedOrders({
    required String sessionId,
    int limit = 3,
  }) async {
    final response = await _client.get(
      _buildWebAppUri('/reorders/recent', {
        'sessionId': sessionId,
        'limit': limit.toString(),
      }),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Recommendations fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is List) {
      return results
          .whereType<Map<String, dynamic>>()
          .map(RecommendedOrder.fromJson)
          .toList();
    }
    return [];
  }

  Future<List<RecommendedOrder>> fetchStoreRecommendations({
    required String sessionId,
    required String storeId,
    int limit = 3,
  }) async {
    final response = await _client.get(
      _buildWebAppUri('/reorders/top', {
        'sessionId': sessionId,
        'storeId': storeId,
        'limit': limit.toString(),
      }),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Store recommendations failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is List) {
      return results
          .whereType<Map<String, dynamic>>()
          .map(RecommendedOrder.fromJson)
          .toList();
    }
    return [];
  }
}

part of 'channel_gateway_api.dart';

mixin ChannelGatewayStoreApi on ChannelGatewayApiBase {
  Future<List<StoreChoice>> searchStores(String query) async {
    final response = await _client.get(
      _buildWebAppUri('/stores/search', {'q': query}),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Store search failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final results = payload['results'];
    if (results is List) {
      return results
          .whereType<Map<String, dynamic>>()
          .map(StoreChoice.fromJson)
          .toList();
    }
    return [];
  }

  Future<void> selectStore({
    required String sessionId,
    required String storeId,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/stores/select'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': sessionId, 'storeId': storeId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Store select failed (${response.statusCode})');
    }
  }

  Future<StoreChoice?> fetchStoreDetails(String storeId) async {
    if (storeId.isEmpty) {
      return null;
    }
    final response = await _client.get(
      _buildWebAppUri('/stores/$storeId'),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Store lookup failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return StoreChoice.fromJson(payload);
  }
}

part of 'channel_gateway_api.dart';

mixin ChannelGatewayMenuApi on ChannelGatewayApiBase {
  Future<MenuSnapshot> fetchMenu(String storeId) async {
    final response = await _client.get(
      _buildWebAppUri('/stores/$storeId/menu'),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Menu fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return MenuSnapshot.fromJson(payload);
  }
}

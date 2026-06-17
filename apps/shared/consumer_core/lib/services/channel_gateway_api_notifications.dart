part of 'channel_gateway_api.dart';

mixin ChannelGatewayNotificationsApi on ChannelGatewayApiBase {
  Future<void> registerMobileDeviceToken({
    required String sessionId,
    required String deviceToken,
    String? platform,
    String? deviceId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/device-tokens'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'deviceToken': deviceToken,
        'platform': platform,
        'deviceId': deviceId,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Device token register failed (${response.statusCode})');
    }
  }

  Future<void> unregisterMobileDeviceToken({
    required String sessionId,
    required String deviceToken,
    String? signature,
    String? timestamp,
  }) async {
    final request = http.Request('DELETE', _buildUri('/mobile/device-tokens'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'sessionId': sessionId,
      'deviceToken': deviceToken,
      'signature': signature,
      'timestamp': timestamp,
    });
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Device token unregister failed (${response.statusCode})',
      );
    }
  }
}

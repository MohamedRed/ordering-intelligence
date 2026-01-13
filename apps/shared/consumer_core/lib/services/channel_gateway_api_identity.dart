part of 'channel_gateway_api.dart';

mixin ChannelGatewayIdentityApi on ChannelGatewayApiBase {
  Future<CustomerProfile> fetchIdentity({required String sessionId}) async {
    final response = await _client.get(
      _buildWebAppUri('/identity', {'sessionId': sessionId}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Identity fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CustomerProfile.fromJson(payload);
  }

  Future<LinkToken> startIdentityLink({
    required String sessionId,
    required String targetChannel,
    required bool consent,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/identity/link/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'targetChannel': targetChannel,
        'consent': consent,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Link start failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return LinkToken.fromJson(payload);
  }

  Future<CustomerProfile> completeIdentityLink({
    required String sessionId,
    required String token,
    required bool consent,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/identity/link/complete'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'token': token,
        'consent': consent,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Link complete failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CustomerProfile.fromJson(payload);
  }

  Future<CustomerProfile> unlinkIdentity({
    required String sessionId,
    required String channel,
    required String userId,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/identity/unlink'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'channel': channel,
        'userId': userId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Unlink failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CustomerProfile.fromJson(payload);
  }

  Future<CustomerProfile> updateFuelPreauthCap({
    required String sessionId,
    required int fuelPreauthCapCents,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/identity/fuel-preauth-cap'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'fuelPreauthCapCents': fuelPreauthCapCents,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Fuel cap update failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return CustomerProfile.fromJson(payload);
  }
}

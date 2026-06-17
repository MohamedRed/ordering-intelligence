part of 'channel_gateway_api.dart';

mixin ChannelGatewaySessionApi on ChannelGatewayApiBase {
  Future<SessionInfo> startSession({
    required String initData,
    String? storeId,
    String? locale,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/session/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'initData': initData,
        'storeId': storeId,
        'locale': locale,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Session start failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInfo.fromJson(payload);
  }

  Future<SessionInfo> startDiscordSession({
    required String code,
    required String redirectUri,
    String? accessToken,
    String? storeId,
    String? locale,
    bool startGroupOrder = false,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/session/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'redirectUri': redirectUri,
        'accessToken': accessToken,
        'storeId': storeId,
        'locale': locale,
        'startGroupOrder': startGroupOrder,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Session start failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInfo.fromJson(payload);
  }

  Future<SessionInfo> startSnapchatSession({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    String? storeId,
    String? locale,
    bool startGroupOrder = false,
  }) async {
    final response = await _client.post(
      _buildWebAppUri('/session/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'codeVerifier': codeVerifier,
        'redirectUri': redirectUri,
        'storeId': storeId,
        'locale': locale,
        'startGroupOrder': startGroupOrder,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Session start failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInfo.fromJson(payload);
  }

  Future<SessionInfo> startMobileSession({
    required AuthSession auth,
    String? storeId,
    String? locale,
    String? clientVersion,
    String? clientPlatform,
    String? clientApp,
    String? clientOs,
    String? clientOsVersion,
    String? deviceId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.post(
      _buildUri('/mobile/session/start'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'provider': auth.provider.id,
        'providerUserId': auth.subject,
        'displayName': auth.displayName,
        'accessToken': auth.accessToken,
        'authCode': auth.authCode,
        'codeVerifier': auth.codeVerifier,
        'redirectUri': auth.redirectUri,
        'storeId': storeId,
        'locale': locale,
        'clientVersion': clientVersion,
        'clientPlatform': clientPlatform,
        'clientApp': clientApp,
        'clientOs': clientOs,
        'clientOsVersion': clientOsVersion,
        'deviceId': deviceId,
        'signature': signature,
        'timestamp': timestamp,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mobile session start failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInfo.fromJson(payload);
  }

  Future<SessionInfo> fetchMobileSession({
    required String sessionId,
    String? signature,
    String? timestamp,
  }) async {
    final response = await _client.get(
      _buildUri('/mobile/session', {
        'sessionId': sessionId,
        if (signature != null) 'signature': signature,
        if (timestamp != null) 'timestamp': timestamp,
      }),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mobile session fetch failed (${response.statusCode})');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return SessionInfo.fromJson(payload);
  }

  Future<void> endMobileSession({
    required String sessionId,
    String? signature,
    String? timestamp,
  }) async {
    final request = http.Request('DELETE', _buildUri('/mobile/session'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'sessionId': sessionId,
      'signature': signature,
      'timestamp': timestamp,
    });
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mobile session end failed (${response.statusCode})');
    }
  }
}

part of 'channel_gateway_api.dart';

mixin ChannelGatewayChatApi on ChannelGatewayApiBase {
  Future<ChatResponse> sendChatTurn({
    required String sessionId,
    String? text,
    Uint8List? audioBytes,
    String? audioMime,
    String? seededIntro,
    List<String>? seededCategories,
    String? seededSource,
  }) async {
    final payload = <String, dynamic>{'sessionId': sessionId, 'text': text};
    if (seededIntro != null && seededIntro.trim().isNotEmpty) {
      payload['seededIntro'] = seededIntro.trim();
    }
    if (seededSource != null && seededSource.trim().isNotEmpty) {
      payload['seededSource'] = seededSource.trim();
    }
    if (seededCategories != null && seededCategories.isNotEmpty) {
      final cleaned = seededCategories
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      if (cleaned.isNotEmpty) {
        payload['seededCategories'] = cleaned;
      }
    }
    if (audioBytes != null && audioBytes.isNotEmpty) {
      payload['audioBase64'] = base64Encode(audioBytes);
      payload['audioMime'] = audioMime ?? 'audio/webm';
    }
    final response = await _client.post(
      _buildWebAppUri('/chat/turn'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Chat failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _decodeChatResponse(body);
  }

  Future<void> prewarmChat({
    required String sessionId,
    String? seededIntro,
    List<String>? seededCategories,
    String? seededSource,
  }) async {
    final payload = <String, dynamic>{'sessionId': sessionId};
    if (seededIntro != null && seededIntro.trim().isNotEmpty) {
      payload['seededIntro'] = seededIntro.trim();
    }
    if (seededSource != null && seededSource.trim().isNotEmpty) {
      payload['seededSource'] = seededSource.trim();
    }
    if (seededCategories != null && seededCategories.isNotEmpty) {
      final cleaned = seededCategories
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      if (cleaned.isNotEmpty) {
        payload['seededCategories'] = cleaned;
      }
    }
    final response = await _client.post(
      _buildWebAppUri('/chat/prewarm'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Chat prewarm failed (${response.statusCode})');
    }
  }
}

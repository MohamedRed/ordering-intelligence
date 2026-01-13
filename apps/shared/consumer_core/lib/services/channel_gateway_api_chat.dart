part of 'channel_gateway_api.dart';

mixin ChannelGatewayChatApi on ChannelGatewayApiBase {
  Future<ChatResponse> sendChatTurn({
    required String sessionId,
    String? text,
    Uint8List? audioBytes,
    String? audioMime,
  }) async {
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'text': text,
    };
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
}

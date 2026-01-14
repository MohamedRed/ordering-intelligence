part of 'channel_gateway_api.dart';

ChatResponse _decodeChatResponse(Map<String, dynamic> body) {
  final messages = <ChatMessage>[];
  final toolCalls = <ChatToolCall>[];
  final rawMessages = body['messages'];
  if (rawMessages is List) {
    for (final entry in rawMessages) {
      if (entry is! Map) continue;
      final role = (entry['role'] ?? 'assistant').toString();
      final text = (entry['text'] ?? '').toString();
      final options = _decodeChatOptions(entry['options']);
      final products = _decodeChatProducts(entry['products']);
      final selectionMode = entry['selectionMode'] ?? entry['selection_mode'];
      final minSelections = _toInt(
        entry['minSelections'] ?? entry['min_selections'],
      );
      final maxSelections = _toInt(
        entry['maxSelections'] ?? entry['max_selections'],
      );
      final confirmLabel =
          entry['confirmLabel']?.toString() ??
          entry['confirm_label']?.toString();
      final toolCallId =
          entry['toolCallId']?.toString() ?? entry['tool_call_id']?.toString();
      final toolName =
          entry['toolName']?.toString() ?? entry['tool_name']?.toString();
      Uint8List? audioBytes;
      final audioBase64 =
          entry['audioBase64'] ?? entry['audio_base64'] ?? entry['audio'];
      if (audioBase64 is String && audioBase64.isNotEmpty) {
        try {
          audioBytes = base64Decode(audioBase64);
        } catch (_) {}
      }
      final audioMime =
          entry['audioMime']?.toString() ?? entry['audio_mime']?.toString();
      messages.add(
        ChatMessage(
          id: _chatResponseId(),
          role: role == 'user' ? ChatRole.user : ChatRole.assistant,
          text: text.isEmpty ? null : text,
          options: options,
          products: products,
          audioBytes: audioBytes,
          audioMime: audioMime,
          toolCallId: toolCallId,
          toolName: toolName,
          selectionMode: selectionMode?.toString(),
          minSelections: minSelections,
          maxSelections: maxSelections,
          confirmLabel: confirmLabel,
        ),
      );
    }
  } else if (body['text'] != null) {
    final text = body['text'].toString();
    if (text.trim().isNotEmpty) {
      messages.add(
        ChatMessage(
          id: _chatResponseId(),
          role: ChatRole.assistant,
          text: text,
        ),
      );
    }
  }
  final rawToolCalls = body['toolCalls'] ?? body['tool_calls'];
  if (rawToolCalls is List) {
    for (final entry in rawToolCalls) {
      if (entry is! Map) continue;
      final name = (entry['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final id =
          (entry['id'] ?? entry['toolCallId'] ?? entry['tool_call_id'] ?? '')
              .toString();
      final args = <String, dynamic>{};
      final rawArgs = entry['arguments'];
      if (rawArgs is Map) {
        rawArgs.forEach((key, value) => args[key.toString()] = value);
      }
      toolCalls.add(ChatToolCall(id: id, name: name, arguments: args));
    }
  }
  if (messages.isEmpty && body['text'] == null && body['message'] != null) {
    final text = body['message'].toString();
    if (text.trim().isNotEmpty) {
      messages.add(
        ChatMessage(
          id: _chatResponseId(),
          role: ChatRole.assistant,
          text: text,
        ),
      );
    }
  }
  return ChatResponse(messages: messages, toolCalls: toolCalls);
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

List<ChatOption> _decodeChatOptions(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (option) => ChatOption(
          label: (option['label'] ?? option['text'] ?? '').toString(),
          payload: option['payload']?.toString(),
          toolName:
              option['toolName']?.toString() ?? option['tool_name']?.toString(),
        ),
      )
      .where((option) => option.label.trim().isNotEmpty)
      .toList();
}

List<ChatProduct> _decodeChatProducts(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (product) => ChatProduct(
          id: (product['id'] ?? '').toString(),
          name: (product['name'] ?? '').toString(),
          description: (product['description'] ?? '').toString(),
          priceLabel: (product['priceLabel'] ?? product['price'] ?? '')
              .toString(),
          imageUrl: (product['imageUrl'] ?? product['image'] ?? '').toString(),
        ),
      )
      .where((product) => product.name.trim().isNotEmpty)
      .toList();
}

String _chatResponseId() => DateTime.now().microsecondsSinceEpoch.toString();

import 'dart:typed_data';

enum MiniAppSegment { chat, browse }

enum ChatRole { user, assistant }

class ChatProduct {
  const ChatProduct({
    required this.id,
    required this.name,
    this.description = '',
    this.priceLabel = '',
    this.imageUrl = '',
  });

  final String id;
  final String name;
  final String description;
  final String priceLabel;
  final String imageUrl;
}

class ChatOption {
  const ChatOption({required this.label, this.payload, this.toolName});

  final String label;
  final String? payload;
  final String? toolName;
}

class ChatToolCall {
  const ChatToolCall({required this.name, this.arguments = const {}});

  final String name;
  final Map<String, dynamic> arguments;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    this.text,
    this.products = const [],
    this.options = const [],
    this.audioBytes,
    this.audioMime,
  });

  final String id;
  final ChatRole role;
  final String? text;
  final List<ChatProduct> products;
  final List<ChatOption> options;
  final Uint8List? audioBytes;
  final String? audioMime;

  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) ||
      products.isNotEmpty ||
      options.isNotEmpty ||
      audioBytes != null;
}

class ChatResponse {
  const ChatResponse({this.messages = const [], this.toolCalls = const []});

  final List<ChatMessage> messages;
  final List<ChatToolCall> toolCalls;
}

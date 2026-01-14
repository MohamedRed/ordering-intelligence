import 'dart:typed_data';

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
  const ChatToolCall({
    required this.name,
    this.id = '',
    this.arguments = const {},
  });

  final String id;
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
    this.toolCallId,
    this.toolName,
    this.selectionMode,
    this.minSelections,
    this.maxSelections,
    this.confirmLabel,
  });

  final String id;
  final ChatRole role;
  final String? text;
  final List<ChatProduct> products;
  final List<ChatOption> options;
  final Uint8List? audioBytes;
  final String? audioMime;
  final String? toolCallId;
  final String? toolName;
  final String? selectionMode;
  final int? minSelections;
  final int? maxSelections;
  final String? confirmLabel;

  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) ||
      products.isNotEmpty ||
      options.isNotEmpty ||
      audioBytes != null;

  bool get isMultiSelect =>
      selectionMode?.toLowerCase() == 'multi' ||
      (maxSelections != null && maxSelections! > 1) ||
      (minSelections != null && minSelections! > 1);
}

class ChatResponse {
  const ChatResponse({this.messages = const [], this.toolCalls = const []});

  final List<ChatMessage> messages;
  final List<ChatToolCall> toolCalls;
}

class ChatToolResult {
  const ChatToolResult({
    required this.toolCallId,
    this.name = '',
    this.result,
    this.isError = false,
  });

  final String toolCallId;
  final String name;
  final dynamic result;
  final bool isError;

  Map<String, dynamic> toJson() => {
    'toolCallId': toolCallId,
    if (name.isNotEmpty) 'name': name,
    if (result != null) 'result': result,
    if (isError) 'isError': true,
  };
}

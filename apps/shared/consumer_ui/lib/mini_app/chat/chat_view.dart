import 'package:flutter/material.dart';

import 'chat_composer.dart';
import 'chat_message_list.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatView extends StatelessWidget {
  const ChatView({
    super.key,
    required this.messages,
    required this.onSend,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onProductSelected,
    required this.onToggleRecording,
    required this.controller,
    this.scrollController,
    this.isLoading = false,
    this.isRecording = false,
    this.isSending = false,
    this.canRecord = true,
  });

  final List<ChatMessage> messages;
  final VoidCallback onSend;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final ValueChanged<ChatProduct> onProductSelected;
  final VoidCallback onToggleRecording;
  final TextEditingController controller;
  final ScrollController? scrollController;
  final bool isLoading;
  final bool isRecording;
  final bool isSending;
  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ChatMessageList(
            messages: messages,
            onOptionSelected: onOptionSelected,
            onOptionsConfirmed: onOptionsConfirmed,
            onProductSelected: onProductSelected,
            controller: scrollController,
            isLoading: isLoading,
          ),
        ),
        ChatComposer(
          controller: controller,
          onSend: onSend,
          onToggleRecording: onToggleRecording,
          isRecording: isRecording,
          isSending: isSending,
          canRecord: canRecord,
        ),
      ],
    );
  }
}

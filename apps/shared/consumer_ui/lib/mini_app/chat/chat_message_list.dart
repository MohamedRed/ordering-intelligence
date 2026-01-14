import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'chat_message_bubble.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onProductSelected,
    this.controller,
    this.isLoading = false,
  });

  final List<ChatMessage> messages;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final ValueChanged<ChatProduct> onProductSelected;
  final ScrollController? controller;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Start with a category or ask a question.',
          style: theme.textTheme.muted,
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: messages.length + (isLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final message = messages[index];
        return ChatMessageBubble(
          message: message,
          onOptionSelected: onOptionSelected,
          onOptionsConfirmed: onOptionsConfirmed,
          onProductSelected: onProductSelected,
        );
      },
    );
  }
}

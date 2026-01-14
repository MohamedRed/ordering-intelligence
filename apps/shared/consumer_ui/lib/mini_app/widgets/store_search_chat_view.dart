import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../chat/chat_view.dart';
import 'package:consumer_core/consumer_core.dart';

class StoreSearchChatView extends StatelessWidget {
  const StoreSearchChatView({
    super.key,
    required this.messages,
    required this.controller,
    required this.searching,
    required this.onSend,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onBack,
  });

  final List<ChatMessage> messages;
  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSend;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Search stores',
                  style: theme.textTheme.h2,
                ),
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type a store name and pick one from the results.',
            style: theme.textTheme.muted,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ChatView(
              messages: messages,
              controller: controller,
              onSend: onSend,
              onOptionSelected: onOptionSelected,
              onOptionsConfirmed: onOptionsConfirmed,
              onProductSelected: (_) {},
              onToggleRecording: () {},
              isLoading: searching,
              isSending: searching,
              canRecord: false,
              placeholder: 'Search stores...',
            ),
          ),
        ],
      ),
    );
  }
}

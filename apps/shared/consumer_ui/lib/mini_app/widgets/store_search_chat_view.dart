import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../chat/chat_view.dart';
import 'store_inline_suggestions.dart';
import 'package:consumer_core/consumer_core.dart';

class StoreSearchChatView extends StatelessWidget {
  const StoreSearchChatView({
    super.key,
    required this.messages,
    required this.controller,
    required this.searching,
    required this.searchResults,
    required this.searchError,
    required this.onSend,
    required this.onOptionSelected,
    required this.onOptionsConfirmed,
    required this.onSelectSuggestion,
    required this.onBack,
  });

  final List<ChatMessage> messages;
  final TextEditingController controller;
  final bool searching;
  final List<StoreChoice> searchResults;
  final String? searchError;
  final VoidCallback onSend;
  final void Function(ChatMessage, ChatOption) onOptionSelected;
  final void Function(ChatMessage, List<ChatOption>) onOptionsConfirmed;
  final ValueChanged<StoreChoice> onSelectSuggestion;
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
              footer: _buildSuggestions(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final theme = ShadTheme.of(context);
    final hasQuery = controller.text.trim().isNotEmpty;
    if (!hasQuery && searchError == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (searchError != null)
            ShadAlert.destructive(
              title: const Text('Search failed'),
              description: Text(searchError!),
            ),
          if (searching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (hasQuery && searchResults.isNotEmpty) ...[
            if (searchError != null || searching) const SizedBox(height: 8),
            StoreInlineSuggestions(
              results: searchResults,
              onSelect: onSelectSuggestion,
              title: 'Suggestions',
              maxItems: 6,
            ),
          ],
          if (hasQuery && searchResults.isEmpty && !searching && searchError == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No suggestions yet.',
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

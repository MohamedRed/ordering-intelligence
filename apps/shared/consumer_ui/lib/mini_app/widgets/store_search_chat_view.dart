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
    this.onBack,
    this.onOpenMenu,
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
  final VoidCallback? onBack;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final showHeaderActions = onBack != null || onOpenMenu != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeaderActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                if (onOpenMenu != null)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: onOpenMenu,
                    child: const Icon(Icons.menu, size: 18),
                  ),
                if (onOpenMenu != null) const SizedBox(width: 8),
                if (onBack != null)
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: onBack,
                    child: const Text('Back'),
                  ),
                const Spacer(),
              ],
            ),
          ),
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
              axis: Axis.vertical,
            ),
          ],
          if (hasQuery &&
              searchResults.isEmpty &&
              !searching &&
              searchError == null)
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

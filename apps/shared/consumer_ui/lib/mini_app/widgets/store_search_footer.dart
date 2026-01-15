import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:consumer_core/consumer_core.dart';

import 'store_inline_suggestions.dart';

class StoreSearchFooter extends StatelessWidget {
  const StoreSearchFooter({
    super.key,
    required this.controller,
    required this.searching,
    required this.searchResults,
    required this.searchError,
    required this.onSelectSuggestion,
    this.onStartSingle,
    this.onStartGroup,
    this.actionsOnlyTap = false,
  });

  final TextEditingController controller;
  final bool searching;
  final List<StoreChoice> searchResults;
  final String? searchError;
  final ValueChanged<StoreChoice> onSelectSuggestion;
  final ValueChanged<StoreChoice>? onStartSingle;
  final ValueChanged<StoreChoice>? onStartGroup;
  final bool actionsOnlyTap;

  @override
  Widget build(BuildContext context) {
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
              onStartSingle: onStartSingle,
              onStartGroup: onStartGroup,
              actionsOnlyTap: actionsOnlyTap,
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

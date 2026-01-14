import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'store_logo.dart';
import 'package:consumer_core/consumer_core.dart';

class StoreInlineSuggestions extends StatelessWidget {
  const StoreInlineSuggestions({
    super.key,
    required this.results,
    required this.onSelect,
    this.title = 'Suggestions',
    this.maxItems = 8,
  });

  final List<StoreChoice> results;
  final ValueChanged<StoreChoice> onSelect;
  final String title;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final visible = results.take(maxItems).toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShadTheme.of(context).textTheme.muted),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final store = visible[index];
              return _StoreSuggestionCard(
                store: store,
                onTap: () => onSelect(store),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StoreSuggestionCard extends StatelessWidget {
  const _StoreSuggestionCard({
    required this.store,
    required this.onTap,
  });

  final StoreChoice store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final name = store.name.isEmpty ? store.storeId : store.name;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Row(
          children: [
            StoreLogo(
              name: name,
              logoUrl: store.logoUrl,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

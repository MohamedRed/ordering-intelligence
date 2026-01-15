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
    this.axis = Axis.horizontal,
    this.onStartSingle,
    this.onStartGroup,
  });

  final List<StoreChoice> results;
  final ValueChanged<StoreChoice> onSelect;
  final String title;
  final int maxItems;
  final Axis axis;
  final ValueChanged<StoreChoice>? onStartSingle;
  final ValueChanged<StoreChoice>? onStartGroup;

  @override
  Widget build(BuildContext context) {
    final visible = results.take(maxItems).toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    if (axis == Axis.vertical) {
      final showActions = onStartSingle != null || onStartGroup != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ShadTheme.of(context).textTheme.muted),
          const SizedBox(height: 8),
          for (var index = 0; index < visible.length; index++) ...[
            _StoreSuggestionCard(
              store: visible[index],
              onTap: () => onSelect(visible[index]),
              expand: true,
              showActions: showActions,
              onStartSingle: onStartSingle,
              onStartGroup: onStartGroup,
            ),
            if (index < visible.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
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
                showActions: false,
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
    this.expand = false,
    this.showActions = false,
    this.onStartSingle,
    this.onStartGroup,
  });

  final StoreChoice store;
  final VoidCallback onTap;
  final bool expand;
  final bool showActions;
  final ValueChanged<StoreChoice>? onStartSingle;
  final ValueChanged<StoreChoice>? onStartGroup;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final name = store.name.isEmpty ? store.storeId : store.name;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: expand ? double.infinity : 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  StoreLogo(name: name, logoUrl: store.logoUrl, size: 28),
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
            if (showActions) ...[
              const SizedBox(width: 8),
              Column(
                children: [
                  if (onStartSingle != null)
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: () => onStartSingle!(store),
                      child: const Icon(Icons.person_outline, size: 16),
                    ),
                  if (onStartGroup != null) ...[
                    const SizedBox(height: 6),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: () => onStartGroup!(store),
                      child: const Icon(Icons.group_outlined, size: 16),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

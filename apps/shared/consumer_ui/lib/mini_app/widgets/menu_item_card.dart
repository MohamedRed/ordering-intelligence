import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:consumer_core/consumer_core.dart';
import 'menu_item_image.dart';

class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    required this.formatPrice,
  });

  final MenuItem item;
  final VoidCallback onAdd;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isAvailable = item.available;
    final buttonIcon = item.modifierGroups.isNotEmpty ? Icons.tune : Icons.add;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MenuItemImage(url: item.imageUrl, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: theme.textTheme.muted,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.priceCents > 0)
                      Text(
                        formatPrice(item.priceCents),
                        style: theme.textTheme.small,
                      ),
                    if (!isAvailable) ...[
                      const SizedBox(width: 8),
                      Text('Unavailable', style: theme.textTheme.muted),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadButton(
            size: ShadButtonSize.sm,
            onPressed: isAvailable ? onAdd : null,
            child: Icon(buttonIcon, size: 18),
          ),
        ],
      ),
    );
  }
}

import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import 'menu_item_image.dart';
import 'minimal_card.dart';

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
    const double cardHeight = 112;
    final textTheme = ShadTheme.of(context).textTheme;
    final haptics = MiniAppScope.of(context).haptics;
    return MinimalCard(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: cardHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MenuItemImage(url: item.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: textTheme.large,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.description,
                      style: textTheme.muted,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(formatPrice(item.priceCents), style: textTheme.small),
                  const Spacer(),
                ],
              ),
            ),
            ShadButton(
              onPressed: () {
                haptics.impact();
                onAdd();
              },
              child: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

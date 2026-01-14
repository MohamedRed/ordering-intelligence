import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../widgets/menu_item_image.dart';
import 'package:consumer_core/consumer_core.dart';

class ChatProductCard extends StatelessWidget {
  const ChatProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  final ChatProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MenuItemImage(
              url: product.imageUrl,
              size: 56,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.small,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description,
                      style: theme.textTheme.muted,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (product.priceLabel.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      product.priceLabel,
                      style: theme.textTheme.small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

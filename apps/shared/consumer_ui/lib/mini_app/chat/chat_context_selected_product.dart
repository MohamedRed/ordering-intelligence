import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import '../widgets/menu_item_image.dart';

class ChatSelectedProductChip extends StatelessWidget {
  const ChatSelectedProductChip({
    super.key,
    required this.product,
    required this.onClear,
  });

  final ChatProduct product;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MenuItemImage(url: product.imageUrl, size: 28),
          const SizedBox(width: 8),
          Text(product.name, style: theme.textTheme.small),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () {
                haptics.selection();
                onClear?.call();
              },
              child: const Icon(Icons.close, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../mini_app_scope.dart';
import '../widgets/minimal_card.dart';

class ChatHeaderCard extends StatelessWidget {
  const ChatHeaderCard({
    super.key,
    required this.storeName,
    required this.subtitle,
    this.cartLabel,
    this.onOpenCart,
    this.onChangeStore,
    this.onOpenMenu,
    this.contextSection,
  });

  final String storeName;
  final String subtitle;
  final String? cartLabel;
  final VoidCallback? onOpenCart;
  final VoidCallback? onChangeStore;
  final VoidCallback? onOpenMenu;
  final Widget? contextSection;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    return MinimalCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: theme.colorScheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onOpenMenu != null) ...[
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () {
                    haptics.selection();
                    onOpenMenu?.call();
                  },
                  child: const Icon(Icons.menu, size: 18),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: theme.textTheme.h3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.muted,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (onChangeStore != null)
                ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () {
                    haptics.selection();
                    onChangeStore?.call();
                  },
                  child: const Text('Change'),
                ),
            ],
          ),
          if (cartLabel != null && cartLabel!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 16,
                  color: theme.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(cartLabel!, style: theme.textTheme.small)),
                if (onOpenCart != null)
                  ShadButton(
                    size: ShadButtonSize.sm,
                    onPressed: () {
                      haptics.selection();
                      onOpenCart?.call();
                    },
                    child: const Text('Cart'),
                  ),
              ],
            ),
          ],
          if (contextSection != null) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: theme.colorScheme.border),
            const SizedBox(height: 10),
            contextSection!,
          ],
        ],
      ),
    );
  }
}

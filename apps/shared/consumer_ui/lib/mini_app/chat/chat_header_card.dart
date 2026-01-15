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
    this.onBack,
    this.onOpenCart,
    this.onChangeStore,
    this.onOpenMenu,
    this.contextSection,
    this.centerTitle = false,
  });

  final String storeName;
  final String subtitle;
  final String? cartLabel;
  final VoidCallback? onBack;
  final VoidCallback? onOpenCart;
  final VoidCallback? onChangeStore;
  final VoidCallback? onOpenMenu;
  final Widget? contextSection;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final haptics = MiniAppScope.hapticsOf(context);
    final hasCart = cartLabel != null && cartLabel!.isNotEmpty;
    final leadingButtons = <Widget>[
      if (onOpenMenu != null)
        _HeaderIconButton(
          icon: Icons.menu,
          onPressed: () {
            haptics.selection();
            onOpenMenu?.call();
          },
        ),
      if (onBack != null)
        _HeaderIconButton(
          icon: Icons.arrow_back,
          onPressed: () {
            haptics.selection();
            onBack?.call();
          },
        ),
    ];
    final trailingWidget = onChangeStore == null
        ? const SizedBox(width: 32)
        : ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () {
              haptics.selection();
              onChangeStore?.call();
            },
            child: const Text('Change'),
          );
    final titleText = Text(
      storeName,
      style: theme.textTheme.h3,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centerTitle ? TextAlign.center : TextAlign.left,
    );
    final subtitleText = subtitle.trim().isNotEmpty
        ? Text(
            subtitle,
            style: theme.textTheme.muted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: centerTitle ? TextAlign.center : TextAlign.left,
          )
        : null;
    return MinimalCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: theme.colorScheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (centerTitle)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            for (var i = 0; i < leadingButtons.length; i++) ...[
                              leadingButtons[i],
                              if (i < leadingButtons.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      Align(alignment: Alignment.center, child: titleText),
                      Align(
                        alignment: Alignment.centerRight,
                        child: trailingWidget,
                      ),
                    ],
                  ),
                ),
                if (subtitleText != null) ...[
                  const SizedBox(height: 4),
                  subtitleText,
                ],
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leadingButtons.isNotEmpty) ...[
                  Row(
                    children: [
                      for (var i = 0; i < leadingButtons.length; i++) ...[
                        leadingButtons[i],
                        if (i < leadingButtons.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleText,
                      if (subtitleText != null) ...[
                        const SizedBox(height: 4),
                        subtitleText,
                      ],
                    ],
                  ),
                ),
                trailingWidget,
              ],
            ),
          if (hasCart) ...[
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
            SizedBox(height: hasCart ? 14 : 10),
            contextSection!,
          ],
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      iconSize: 18,
      onPressed: onPressed,
      icon: Icon(icon, color: ShadTheme.of(context).colorScheme.foreground),
    );
  }
}
